// Drives the real ChatBloc on the backend; needs a running server:
//   flutter test test/live --dart-define=API_BASE_URL=http://localhost:8080 \
//     --dart-define=LIVE_TEST=true --dart-define=USE_BACKEND=true
@Tags(['live'])
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinai/api/api_client.dart';
import 'dart:typed_data';

import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/api/session_store.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';

class MemoryStore extends SessionStore {
  SessionData? saved;
  @override
  Future<SessionData?> read() async => saved;
  @override
  Future<void> write(SessionData s) async => saved = s;
  @override
  Future<void> clear() async => saved = null;
}

/// Waits for the first state matching [test].
Future<T> next<T extends ChatState>(ChatBloc bloc, [bool Function(T)? test]) =>
    bloc.stream
        .where((s) => s is T && (test == null || test(s)))
        .cast<T>()
        .first
        .timeout(const Duration(seconds: 8));

void main() {
  const enabled = bool.fromEnvironment('LIVE_TEST') && ApiConfig.useBackend;

  test('chats and messages through the backend', () async {
    FlutterSecureStorage.setMockInitialValues({});
    // Alice is the app's user; Bob writes from another client.
    final alice = ApiClient.instance;
    await alice.startSession(await alice.postPublic(
        '/v1/auth/guest', {'name': 'Alice'}) as Map<String, dynamic>);
    final bob = ApiClient(store: MemoryStore());
    await bob.startSession(await bob.postPublic(
        '/v1/auth/guest', {'name': 'Bob'}) as Map<String, dynamic>);
    LiveSocket.instance.start();
    for (var i = 0; i < 50 && !LiveSocket.instance.connected.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(LiveSocket.instance.connected.value, isTrue);

    // Create a chat.
    final creator = ChatBloc()..add(const CreateChatEvent('Bloc test'));
    final created = await next<ChatCreated>(creator);
    final code = created.code;
    expect(code, hasLength(6));
    await bob.post('/v1/chats/$code/join');

    // Open it and talk.
    final chat = ChatBloc()..add(MessagesSubscribeEvent(code));
    await next<MessagesLoaded>(chat);

    chat.add(SendMessageEvent(chatCode: code, text: 'Привет, Боб'));
    final pending = await next<MessagesLoaded>(
        chat, (s) => s.messages.any((m) => m.text == 'Привет, Боб'));
    expect(pending.messages.last.text, 'Привет, Боб');
    final sent = await next<MessagesLoaded>(chat,
        (s) => s.messages.any((m) => m.text == 'Привет, Боб' && m.createdAt != null));
    expect(sent.messages.where((m) => m.text == 'Привет, Боб'), hasLength(1),
        reason: 'the sending copy is replaced, not duplicated');

    final incomingSoon = next<MessagesLoaded>(
        chat, (s) => s.messages.any((m) => m.text == 'Привет, Алиса'));
    await bob.post('/v1/chats/$code/messages', {'text': 'Привет, Алиса'});
    final incoming = await incomingSoon;
    final bobsMessage =
        incoming.messages.firstWhere((m) => m.text == 'Привет, Алиса');
    expect(bobsMessage.senderName, 'Bob');

    // Bob reads it: Alice sees "seen".
    final seen = next<MessagesLoaded>(chat, (s) => s.seenAt != null);
    await bob.post('/v1/chats/$code/read');
    await seen;

    // Reactions and edits come back live.
    chat.add(ToggleReactionEvent(
        chatCode: code, messageId: bobsMessage.id, reaction: '❤️'));
    await next<MessagesLoaded>(chat, (s) => s.messages
        .any((m) => m.id == bobsMessage.id && m.reactions.values.contains('❤️')));
    final mine = sent.messages.firstWhere((m) => m.text == 'Привет, Боб');
    chat.add(EditMessageEvent(chatCode: code, messageId: mine.id, text: 'Привет!'));
    await next<MessagesLoaded>(
        chat, (s) => s.messages.any((m) => m.id == mine.id && m.isEdited));
    chat.add(DeleteMessageEvent(chatCode: code, messageId: mine.id));
    await next<MessagesLoaded>(chat, (s) => !s.messages.any((m) => m.id == mine.id));

    // The chats list shows the chat with its last message and unread count.
    // Leave the chat first: while it is open, new messages count as read.
    await chat.close();
    final list = ChatBloc()..add(const GetChatsEvent());
    final loaded = await next<ChatsLoaded>(list);
    final row = loaded.chats.firstWhere((c) => c.code == code);
    expect(row.name, 'Bloc test');
    expect(row.isOwner, isTrue);
    expect(row.lastMessage, 'Привет, Алиса');

    final updatedSoon = next<ChatsLoaded>(list, (s) =>
        s.chats.any((c) => c.code == code && c.lastMessage == 'Ещё одно'));
    await bob.post('/v1/chats/$code/messages', {'text': 'Ещё одно'});
    final updated = await updatedSoon;
    expect(updated.chats.firstWhere((c) => c.code == code).hasUnread, isTrue);

    // History pages.
    for (var i = 0; i < 35; i++) {
      await bob.post('/v1/chats/$code/messages', {'text': 'n$i'});
    }
    final paged = ChatBloc()..add(MessagesSubscribeEvent(code));
    final first = await next<MessagesLoaded>(paged);
    expect(first.messages, hasLength(30));
    expect(first.hasMore, isTrue);
    paged.add(const LoadMoreMessagesEvent());
    final more = await next<MessagesLoaded>(
        paged, (s) => s.messages.length > 30 && !s.isLoadingMore);
    expect(more.messages.first.text, 'Привет, Алиса');

    // Owner deletes the chat.
    creator.add(DeleteChatEvent(code));
    await next<ChatDeleted>(creator);

    for (final bloc in [creator, list, paged]) {
      await bloc.close();
    }
    await LiveSocket.instance.stop();
  }, skip: enabled ? false : 'needs a backend; see the top of the file');

  test('chat info stays live', () async {
    final alice = ApiClient.instance;
    if (!alice.isSignedIn) {
      FlutterSecureStorage.setMockInitialValues({});
      await alice.startSession(await alice.postPublic(
          '/v1/auth/guest', {'name': 'Alice'}) as Map<String, dynamic>);
    }
    LiveSocket.instance.start();
    for (var i = 0; i < 50 && !LiveSocket.instance.connected.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final bob = ApiClient(store: MemoryStore());
    await bob.startSession(await bob.postPublic(
        '/v1/auth/guest', {'name': 'Bob'}) as Map<String, dynamic>);
    final bobId = bob.userId!;

    final code = await ChatsApi.instance.create('Info test');
    final updates = watchChat(code).asBroadcastStream();
    Future<Map<String, dynamic>?> until(bool Function(Map<String, dynamic>?) f) =>
        updates.firstWhere(f).timeout(const Duration(seconds: 8));

    final first = await until((c) => c != null);
    expect(first!['name'], 'Info test');
    expect(first['ownerId'], alice.userId);

    // Bob joins and comes online.
    final joined = until((c) => (c?['participantIds'] as List?)?.contains(bobId) ?? false);
    await bob.post('/v1/chats/$code/join');
    await joined;
    final online = until((c) => c?['members']?[bobId]?['online'] == true);
    final bobSocket = LiveSocket(bob)..start();
    await online;
    final offline = until((c) =>
        c?['members']?[bobId]?['online'] == false &&
        c?['members']?[bobId]?['lastSeen'] != null);
    await bobSocket.stop();
    await offline;

    // Rename and photo come through live.
    final renamed = until((c) => c?['name'] == 'Переименован');
    await ChatsApi.instance.rename(code, 'Переименован');
    await renamed;
    final photo = until((c) =>
        (c?['photoUrl'] as String?)?.startsWith(ApiConfig.baseUrl) ?? false);
    await ChatsApi.instance.setPhoto(code, Uint8List.fromList([1, 2, 3]), 'image/jpeg');
    await photo;

    // Bob can't rename; the owner removes him and his view ends.
    await expectLater(ChatsApi(bob).rename(code, 'x'), throwsA(isA<ApiException>()));
    final gone = until((c) => !((c?['participantIds'] as List?)?.contains(bobId) ?? true));
    await ChatsApi.instance.removeMember(code, bobId);
    await gone;

    await ChatsApi.instance.deleteOrLeave(code, isOwner: true);
    await LiveSocket.instance.stop();
  }, skip: enabled ? false : 'needs a backend; see the top of the file');
}
