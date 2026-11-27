import 'package:firebase_auth/firebase_auth.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/live_socket.dart';

/// The signed-in user as the backend knows them.
class ApiUser {
  const ApiUser({
    required this.id,
    required this.name,
    this.photoUrl,
    this.quickReactions,
  });

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        photoUrl: json['photoUrl'] as String?,
        quickReactions:
            (json['quickReactions'] as List?)?.whereType<String>().toList(),
      );

  final String id;
  final String name;
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

  /// Makes sure there is a backend session: the saved one, or a new one
  /// from the current Firebase account.
  Future<void> ensureSignedIn() async {
    if (_api.isSignedIn || await _api.restore()) return;
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
    return ApiUser.fromJson(user);
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

  Future<ApiUser> me() async =>
      ApiUser.fromJson(await _api.get('/v1/me') as Map<String, dynamic>);

  /// Renames the user; kept in step with the Firebase display name while
  /// both are in use.
  Future<ApiUser> rename(String name) async => ApiUser.fromJson(
        await _api.patch('/v1/me', {'name': name}) as Map<String, dynamic>,
      );

  Future<void> setQuickReactions(List<String> list) =>
      _api.patch('/v1/me', {'quickReactions': list});

  Future<void> signOut() => _api.signOut();
}
