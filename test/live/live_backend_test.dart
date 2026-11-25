// Runs against a real backend, so it's skipped unless one is given:
//   flutter test test/live --dart-define=API_BASE_URL=http://localhost:8080 --dart-define=LIVE_TEST=true
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/api/session_store.dart';

class MemoryStore extends SessionStore {
  SessionData? saved;
  @override
  Future<SessionData?> read() async => saved;
  @override
  Future<void> write(SessionData s) async => saved = s;
  @override
  Future<void> clear() async => saved = null;
}

void main() {
  const enabled = bool.fromEnvironment('LIVE_TEST');

  test('client and socket work against the backend', () async {
    final alice = ApiClient(store: MemoryStore());
    final bob = ApiClient(store: MemoryStore());
    await alice.startSession(
        await alice.postPublic('/v1/auth/guest', {'name': 'Live A'}) as Map<String, dynamic>);
    await bob.startSession(
        await bob.postPublic('/v1/auth/guest', {'name': 'Live B'}) as Map<String, dynamic>);

    final socket = LiveSocket(bob)..start();
    final chat = await alice.post('/v1/chats', {'name': 'live'}) as Map<String, dynamic>;
    final code = chat['code'] as String;
    await bob.post('/v1/chats/$code/join');

    final event = socket
        .eventsOf(code)
        .firstWhere((e) => e.type == 'message.created');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await alice.post('/v1/chats/$code/messages', {'text': 'Привет из Flutter'});

    final got = await event.timeout(const Duration(seconds: 5));
    expect(got.data['text'], 'Привет из Flutter');
    expect(got.data['senderName'], 'Live A');

    await alice.delete('/v1/chats/$code');
    await socket.stop();
  }, skip: enabled ? false : 'needs --dart-define=LIVE_TEST=true');
}
