import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/session_store.dart';

/// Keeps the session in memory instead of the keychain.
class MemoryStore extends SessionStore {
  SessionData? saved;

  @override
  Future<SessionData?> read() async => saved;
  @override
  Future<void> write(SessionData s) async => saved = s;
  @override
  Future<void> clear() async => saved = null;
}

http.Response json(int status, Object body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> session(String access, String refresh) => {
      'user': {'id': 'u1', 'name': 'Test'},
      'accessToken': access,
      'refreshToken': refresh,
      'expiresIn': 900,
    };

void main() {
  test('sends the access token and decodes JSON', () async {
    String? auth;
    final api = ApiClient(
      store: MemoryStore(),
      httpClient: MockClient((req) async {
        auth = req.headers['Authorization'];
        return json(200, {'name': 'Даниел'});
      }),
    );
    await api.startSession(session('a1', 'r1'));

    final me = await api.get('/v1/me');
    expect(auth, 'Bearer a1');
    expect(me['name'], 'Даниел');
    expect(api.userId, 'u1');
  });

  test('renews a rejected token once, shared by calls at the same time',
      () async {
    var refreshes = 0;
    final api = ApiClient(
      store: MemoryStore(),
      httpClient: MockClient((req) async {
        if (req.url.path == '/v1/auth/refresh') {
          refreshes++;
          expect(jsonDecode(req.body)['refreshToken'], 'r1');
          return json(200, {'accessToken': 'a2', 'refreshToken': 'r2', 'expiresIn': 900});
        }
        return req.headers['Authorization'] == 'Bearer a2'
            ? json(200, {'ok': true})
            : json(401, {'error': {'code': 'unauthorized', 'message': 'Sign in again'}});
      }),
    );
    await api.startSession(session('a1', 'r1'));

    final results = await Future.wait([
      api.get('/v1/chats'),
      api.get('/v1/me'),
      api.get('/v1/chats/ABC123'),
    ]);
    expect(results.every((r) => r['ok'] == true), isTrue);
    expect(refreshes, 1, reason: 'each refresh token works only once');
  });

  test('signs out when the session is revoked', () async {
    var signedOut = false;
    final store = MemoryStore();
    final api = ApiClient(
      store: store,
      httpClient: MockClient((req) async =>
          json(401, {'error': {'code': 'unauthorized', 'message': 'Sign in again'}})),
    )..onSignedOut = () => signedOut = true;
    await api.startSession(session('a1', 'r1'));

    await expectLater(api.get('/v1/me'), throwsA(isA<ApiException>()));
    expect(signedOut, isTrue);
    expect(api.isSignedIn, isFalse);
    expect(store.saved, isNull);
  });

  test('turns backend errors into ApiException', () async {
    final api = ApiClient(
      store: MemoryStore(),
      httpClient: MockClient((req) async =>
          json(400, {'error': {'code': 'bad_request', 'message': 'Message is empty'}})),
    );
    await api.startSession(session('a1', 'r1'));

    await expectLater(
      api.post('/v1/chats/ABC123/messages', {'text': ''}),
      throwsA(isA<ApiException>()
          .having((e) => e.status, 'status', 400)
          .having((e) => e.message, 'message', 'Message is empty')),
    );
  });

  test('refuses calls when signed out', () async {
    final api = ApiClient(
      store: MemoryStore(),
      httpClient: MockClient((req) async => json(200, {})),
    );
    await expectLater(
      api.get('/v1/me'),
      throwsA(isA<ApiException>().having((e) => e.isUnauthorized, '401', isTrue)),
    );
  });
}
