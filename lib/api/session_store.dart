import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in session: who the user is and the tokens to prove it.
class SessionData {
  const SessionData({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
  });

  final String userId;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;

  /// Refreshed a little before it really runs out, so requests in flight
  /// don't fail on the way.
  bool get accessExpired =>
      DateTime.now().isAfter(accessExpiresAt.subtract(const Duration(seconds: 30)));

  SessionData withTokens({
    required String accessToken,
    required String refreshToken,
    required int expiresIn,
  }) =>
      SessionData(
        userId: userId,
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessExpiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      );
}

/// Keeps the session in the phone's keychain / keystore, not in plain
/// preferences, since the refresh token is a long-lived credential.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _userId = 'session.userId';
  static const _access = 'session.access';
  static const _refresh = 'session.refresh';
  static const _expires = 'session.expires';

  Future<SessionData?> read() async {
    final values = await _storage.readAll();
    final userId = values[_userId];
    final access = values[_access];
    final refresh = values[_refresh];
    final expires = int.tryParse(values[_expires] ?? '');
    if (userId == null || access == null || refresh == null || expires == null) {
      return null;
    }
    return SessionData(
      userId: userId,
      accessToken: access,
      refreshToken: refresh,
      accessExpiresAt: DateTime.fromMillisecondsSinceEpoch(expires),
    );
  }

  Future<void> write(SessionData s) async {
    await _storage.write(key: _userId, value: s.userId);
    await _storage.write(key: _access, value: s.accessToken);
    await _storage.write(key: _refresh, value: s.refreshToken);
    await _storage.write(
      key: _expires,
      value: s.accessExpiresAt.millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> clear() async {
    for (final key in [_userId, _access, _refresh, _expires]) {
      await _storage.delete(key: key);
    }
  }
}
