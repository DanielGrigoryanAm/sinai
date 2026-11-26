import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/session_store.dart';

/// A failed request, with the backend's error code and message.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isUnauthorized => status == 401;
  bool get isNotFound => status == 404;

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// Talks to the backend: JSON in and out, the access token on every call,
/// and a fresh token pair fetched by itself when the old one runs out.
class ApiClient {
  ApiClient({http.Client? httpClient, SessionStore? store})
      : _http = httpClient ?? http.Client(),
        _store = store ?? SessionStore();

  static final instance = ApiClient();

  final http.Client _http;
  final SessionStore _store;

  SessionData? _session;
  Future<SessionData?>? _refreshing;

  /// Called when the session can't be renewed and the user must sign in
  /// again.
  void Function()? onSignedOut;

  /// The signed-in user's id here, once [restore] or a sign-in ran.
  String? get userId => _session?.userId;
  bool get isSignedIn => _session != null;

  /// Loads the saved session; reports whether there was one.
  Future<bool> restore() async {
    _session = await _store.read();
    return _session != null;
  }

  /// Saves a session the backend just started (`{user, accessToken,
  /// refreshToken, expiresIn}`).
  Future<Map<String, dynamic>> startSession(Map<String, dynamic> body) async {
    final user = body['user'] as Map<String, dynamic>;
    final session = SessionData(
      userId: user['id'] as String,
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      accessExpiresAt:
          DateTime.now().add(Duration(seconds: body['expiresIn'] as int)),
    );
    _session = session;
    await _store.write(session);
    return user;
  }

  /// Ends the session here and on the backend.
  Future<void> signOut() async {
    final session = _session;
    _session = null;
    await _store.clear();
    if (session != null) {
      try {
        await _send('POST', '/v1/auth/logout',
            body: {'refreshToken': session.refreshToken}, auth: false);
      } catch (_) {
        // Signed out here either way.
      }
    }
  }

  /// The access token as it is now, for places that can't wait for a
  /// refresh (image widgets); starts one in the background when it is
  /// about to run out.
  String? get currentAccessToken {
    final session = _session;
    if (session != null && session.accessExpired) _refresh();
    return session?.accessToken;
  }

  /// A current access token, refreshed first if needed; null if signed out.
  Future<String?> accessToken() async {
    var session = _session;
    if (session == null) return null;
    if (session.accessExpired) session = await _refresh();
    return session?.accessToken;
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _call('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) =>
      _call('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) =>
      _call('PATCH', path, body: body);
  Future<dynamic> put(String path, Object body) =>
      _call('PUT', path, body: body);
  Future<dynamic> delete(String path) => _call('DELETE', path);

  /// A call made without a session, e.g. to sign in.
  Future<dynamic> postPublic(String path, Object body) =>
      _send('POST', path, body: body, auth: false);

  Future<dynamic> _call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    try {
      return await _send(method, path, body: body, query: query);
    } on ApiException catch (e) {
      // The token may have been revoked or expired early: renew once.
      if (!e.isUnauthorized || _session == null) rethrow;
      if (await _refresh() == null) rethrow;
      return _send(method, path, body: body, query: query);
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool auth = true,
  }) async {
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await accessToken();
      if (token == null) {
        throw const ApiException(401, 'unauthorized', 'Not signed in');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    final request = http.Request(method, ApiConfig.uri(path, query))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    final response = await http.Response.fromStream(
      await _http.send(request).timeout(const Duration(seconds: 20)),
    );
    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      final error = decoded is Map ? decoded['error'] : null;
      throw ApiException(
        response.statusCode,
        error is Map ? '${error['code']}' : 'error',
        error is Map ? '${error['message']}' : 'Request failed',
      );
    }
    return decoded;
  }

  /// Trades the refresh token for a new pair. Calls that need it at the
  /// same time share one refresh, since each refresh token works once.
  Future<SessionData?> _refresh() {
    final pending = _refreshing;
    if (pending != null) return pending;
    final refresh = _renew();
    _refreshing = refresh;
    void done() {
      if (identical(_refreshing, refresh)) _refreshing = null;
    }

    refresh.then((_) => done(), onError: (_) => done());
    return refresh;
  }

  Future<SessionData?> _renew() async {
    {
      try {
        final session = _session;
        if (session == null) return null;
        final body = await _send('POST', '/v1/auth/refresh',
            body: {'refreshToken': session.refreshToken}, auth: false);
        final renewed = session.withTokens(
          accessToken: body['accessToken'] as String,
          refreshToken: body['refreshToken'] as String,
          expiresIn: body['expiresIn'] as int,
        );
        _session = renewed;
        await _store.write(renewed);
        return renewed;
      } on ApiException catch (e) {
        if (e.isUnauthorized) {
          _session = null;
          await _store.clear();
          onSignedOut?.call();
        }
        return null;
      }
    }
  }
}
