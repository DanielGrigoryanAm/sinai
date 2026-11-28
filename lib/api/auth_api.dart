import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/api/local_cache.dart';

/// The signed-in user as the backend knows them.
class ApiUser {
  const ApiUser({
    required this.id,
    required this.name,
    this.code = '',
    this.photoUrl,
    this.quickReactions,
  });

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        code: (json['code'] as String?) ?? '',
        photoUrl: ChatsApi.fileUrl(json['photoUrl']),
        quickReactions:
            (json['quickReactions'] as List?)?.whereType<String>().toList(),
      );

  /// For [LocalCache]; [ApiUser.fromJson] reads it back.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        if (photoUrl != null) 'photoUrl': photoUrl,
        if (quickReactions != null) 'quickReactions': quickReactions,
      };

  final String id;
  final String name;

  /// Their own code, unique, like a username: others find them by it.
  final String code;
  final String? photoUrl;

  /// Their own quick reactions; null for the app's default set.
  final List<String>? quickReactions;
}

/// Signs the user in to the backend.
///
/// Users sign in to Firebase with Google on onboarding. The backend session is made from the Firebase ID
/// token: the backend finds the account by its Firebase uid, or makes a
/// new one the first time.
class AuthApi {
  AuthApi([ApiClient? client]) : _api = client ?? ApiClient.instance;

  static final instance = AuthApi();

  final ApiClient _api;

  static const _cacheName = 'me';

  /// The user as last seen from the backend, kept on the device so the
  /// profile (photo, code, name) shows at once; null until known.
  final current = ValueNotifier<ApiUser?>(null);

  /// The user's profile photo; null when there is none or not known yet.
  String? get photoUrl => current.value?.photoUrl;

  ApiUser _remember(ApiUser user) {
    current.value = user;
    LocalCache.instance.write(_cacheName, user.toJson()).ignore();
    return user;
  }

  /// Shows the saved profile until the backend answers.
  Future<void> _loadCached() async {
    if (current.value != null) return;
    try {
      final json = await LocalCache.instance.read(_cacheName);
      if (json is! Map<String, dynamic>) return;
      final user = ApiUser.fromJson(json);
      if (user.id == _api.userId && current.value == null) {
        current.value = user;
      }
    } catch (e) {
      debugPrint('Cached profile unreadable: $e');
    }
  }

  /// Makes sure there is a backend session: the saved one, or a new one
  /// from the current Firebase account.
  Future<void> ensureSignedIn() async {
    if (_api.isSignedIn || await _api.restore()) {
      await _loadCached();
      return;
    }
    await signInWithFirebase();
  }

  Future<ApiUser> signInWithFirebase() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      throw StateError('Not signed in to Firebase');
    }
    final idToken = await firebaseUser.getIdToken(true);
    // Used by the backend only for a new account. Google names can be
    // longer than the 40 characters it takes.
    final name = (firebaseUser.displayName ?? '').trim();
    final body = await _api.postPublic('/v1/auth/firebase', {
      'idToken': idToken,
      'name': String.fromCharCodes(name.runes.take(40)).trim(),
    });
    final user = await _api.startSession(body as Map<String, dynamic>);
    return _remember(ApiUser.fromJson(user));
  }

  /// After signing in to another Firebase account (Google, phone), moves
  /// the backend session and the live socket over to it too.
  Future<ApiUser> switchToFirebaseAccount() async {
    await LiveSocket.instance.stop();
    await _api.signOut();
    final user = await signInWithFirebase();
    LiveSocket.instance.start();
    return user;
  }

  Future<ApiUser> me() async => _remember(
      ApiUser.fromJson(await _api.get('/v1/me') as Map<String, dynamic>));

  /// Renames the user; kept in step with the Firebase display name while
  /// both are in use.
  Future<ApiUser> rename(String name) async => _remember(ApiUser.fromJson(
        await _api.patch('/v1/me', {'name': name}) as Map<String, dynamic>,
      ));

  /// Uploads [bytes] and makes them the user's profile photo.
  Future<ApiUser> setPhoto(Uint8List bytes, String contentType) async {
    final upload = await _api.post('/v1/me/uploads', {
      'contentType': contentType,
      // Signed into the upload URL: storage refuses any other size.
      'size': bytes.length,
    }) as Map;
    final response = await http.put(
      Uri.parse(upload['uploadUrl'] as String),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'upload', 'Upload failed');
    }
    return _remember(ApiUser.fromJson(await _api.patch('/v1/me', {
      'photoUrl': upload['key'],
    }) as Map<String, dynamic>));
  }

  Future<ApiUser> removePhoto() async => _remember(ApiUser.fromJson(
        await _api.patch('/v1/me', {'photoUrl': ''}) as Map<String, dynamic>,
      ));

  Future<void> setQuickReactions(List<String> list) async {
    await _api.patch('/v1/me', {'quickReactions': list});
    final me = current.value;
    if (me != null) {
      _remember(ApiUser(
        id: me.id,
        name: me.name,
        code: me.code,
        photoUrl: me.photoUrl,
        quickReactions: list,
      ));
    }
  }

  Future<void> signOut() {
    current.value = null;
    return _api.signOut();
  }
}
