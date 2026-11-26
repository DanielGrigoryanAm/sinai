// Drives the real ChatBloc on the backend; needs a running server:
//   flutter test test/live --dart-define=API_BASE_URL=http://localhost:8080 \
//     --dart-define=LIVE_TEST=true --dart-define=USE_BACKEND=true
@Tags(['live'])
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinai/api/api_client.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/features/chat/widgets/chat_games.dart';
import 'package:sinai/features/chat/widgets/checkers_game.dart';
import 'package:sinai/features/chat/widgets/chess_game.dart';
import 'package:sinai/features/chat/widgets/tic_tac_toe.dart';
import 'package:sinai/features/chat/typing_reporter.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/api/media_url.dart';
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

  test('photos: upload, load with the token, media list, search, forward',
      () async {
    final alice = ApiClient.instance;
    if (!alice.isSignedIn) {
      FlutterSecureStorage.setMockInitialValues({});
      await alice.startSession(await alice.postPublic(
          '/v1/auth/guest', {'name': 'Alice'}) as Map<String, dynamic>);
    }
    final api = ChatsApi.instance;
    final code = await api.create('Media test');
    final other = await api.create('Forward target');

    final photo = Uint8List.fromList(List.generate(2048, (i) => i % 251));
    final key = await api.upload(code,
        kind: 'image', contentType: 'image/jpeg', bytes: photo);
    final sent = await api.send(code,
        text: 'фото с подписью', imageKey: key, imageWidth: 10, imageHeight: 10);
    expect(sent.imageUrl, startsWith(ApiConfig.baseUrl));

    // Loads with the token in the address, cached by the address without.
    final source = mediaUrl(sent.imageUrl!);
    expect(source.cacheKey, sent.imageUrl);
    expect(source.url, contains('token='));
    final res = await http.get(Uri.parse(source.url));
    expect(res.statusCode, 200);
    expect(res.bodyBytes, photo);
    expect((await http.get(Uri.parse(sent.imageUrl!))).statusCode, 401);

    final media = await api.media(code, 'image');
    expect(media.single.id, sent.id);
    final found = await api.search(code, 'подпис');
    expect(found.single.id, sent.id);

    await api.forward(fromChat: code, messageId: sent.id, toChat: other);
    final copied = (await api.messages(other)).single;
    expect(copied.forwardedFrom, 'Alice');
    expect(copied.imageUrl, contains('/chats/$other/images/'));
    final copy = await http.get(Uri.parse(mediaUrl(copied.imageUrl!).url));
    expect(copy.bodyBytes, photo);

    await api.deleteOrLeave(code, isOwner: true);
    await api.deleteOrLeave(other, isOwner: true);
  }, skip: enabled ? false : 'needs a backend; see the top of the file');

  test('status line: online, typing, last seen', () async {
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
    final code = await ChatsApi.instance.create('Status test');
    await bob.post('/v1/chats/$code/join');

    final status = ChatStatusController(code);
    Future<void> until(bool Function(ChatStatus?) f) async {
      final done = Completer<void>();
      void check() {
        if (f(status.status.value) && !done.isCompleted) done.complete();
      }
      status.status.addListener(check);
      check();
      await done.future.timeout(const Duration(seconds: 8));
      status.status.removeListener(check);
    }

    final bobSocket = LiveSocket(bob)..start();
    await until((s) => s?.text == 'online');

    bobSocket.sendTyping(code);
    await until((s) => s?.typing == true && s?.text == 'typing…');
    bobSocket.sendTypingStopped(code);
    await until((s) => s?.text == 'online');

    // Sending clears it too.
    bobSocket.sendTyping(code);
    await until((s) => s?.typing == true);
    await bob.post('/v1/chats/$code/messages', {'text': 'готово'});
    await until((s) => s?.text == 'online');

    await bobSocket.stop();
    await until((s) => s?.text == 'last seen just now');

    // Alice typing reaches Bob through TypingReporter.
    final bobEvents = LiveSocket(bob)..start();
    final heard = bobEvents.eventsOf(code).firstWhere((e) => e.type == 'typing');
    for (var i = 0; i < 50 && !bobEvents.connected.value; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final field = TextEditingController();
    final reporter = TypingReporter(chatCode: code, controller: field);
    field.text = 'Прив';
    final typed = await heard.timeout(const Duration(seconds: 5));
    expect(typed.data['name'], 'Alice');
    final stopped =
        bobEvents.eventsOf(code).firstWhere((e) => e.type == 'typing.stop');
    field.clear();
    await stopped.timeout(const Duration(seconds: 5));

    reporter.dispose();
    status.dispose();
    await bobEvents.stop();
    await ChatsApi.instance.deleteOrLeave(code, isOwner: true);
    await LiveSocket.instance.stop();
  }, skip: enabled ? false : 'needs a backend; see the top of the file');

  test('games: start, moves, pick, cancel', () async {
    final alice = ApiClient.instance;
    if (!alice.isSignedIn) {
      FlutterSecureStorage.setMockInitialValues({});
      await alice.startSession(await alice.postPublic(
          '/v1/auth/guest', {'name': 'Alice'}) as Map<String, dynamic>);
    }
    final bob = ApiClient(store: MemoryStore());
    await bob.startSession(await bob.postPublic(
        '/v1/auth/guest', {'name': 'Bob'}) as Map<String, dynamic>);
    final code = await ChatsApi.instance.create('Games test');
    await bob.post('/v1/chats/$code/join');
    Future<Map<String, dynamic>> chat() => ChatsApi.instance.chat(code);

    // Tic-tac-toe is the default pick; Alice starts and plays X.
    await ChatGames.start(code, await chat());
    var ttt = TicTacToe.fromChat(await chat())!;
    expect(ttt.x, alice.userId);
    expect(ttt.isTurnOf(alice.userId!), isTrue);
    await TicTacToe.move(code, ttt, 4);
    var game = (await chat())['game'] as Map;
    expect(game['board'][4], 'x');
    expect(game['turn'], 'o');
    expect(game['by'], alice.userId);
    expect(game['event'], 'move');
    expect(game['pick'], 'ttt', reason: 'a move keeps the rest of the game');

    // Bob's move as O (written whole, the way the app does).
    await bob.patch('/v1/chats/$code', {
      'game': {
        ...game,
        'board': [...game['board']]..[0] = 'o',
        'o': bob.userId, 'turn': 'x', 'by': bob.userId, 'at': 2,
      },
    });
    ttt = TicTacToe.fromChat(await chat())!;
    expect(ttt.o, bob.userId);
    expect(ttt.isTurnOf(alice.userId!), isTrue);
    expect(ChatGames.waitsOnMe(await chat()), isTrue);

    // Picking chess puts the tic-tac-toe game away.
    await ChatGameType.pick(code, await chat(), ChatGameType.chess);
    expect((await chat())['game'], {'pick': 'chess'});
    expect(ChatGameType.pickedIn(await chat()), ChatGameType.chess);

    await ChatGames.start(code, await chat());
    final chess = ChessGame.fromChat(await chat())!;
    expect(chess.white, alice.userId);
    await ChessGame.move(code, chess, 'e2', 'e4');
    final moved = ChessGame.fromChat(await chat())!;
    expect(moved.fen, contains(' b '));
    expect(moved.from, 'e2');
    expect(moved.to, 'e4');

    await ChatGameType.pick(code, await chat(), ChatGameType.checkers);
    await ChatGames.start(code, await chat());
    final checkers = CheckersGame.fromChat(await chat())!;
    expect(checkers.white, alice.userId);
    expect(checkers.legalSteps(), isNotEmpty);

    await ChatGames.cancel(code, await chat());
    expect((await chat())['game'], {'pick': 'checkers'});

    await ChatsApi.instance.deleteOrLeave(code, isOwner: true);
  }, skip: enabled ? false : 'needs a backend; see the top of the file');

  test('quick reactions follow the account', () async {
    final alice = ApiClient.instance;
    if (!alice.isSignedIn) {
      FlutterSecureStorage.setMockInitialValues({});
      await alice.startSession(await alice.postPublic(
          '/v1/auth/guest', {'name': 'Alice'}) as Map<String, dynamic>);
    }
    final store = QuickReactionsStore.instance;
    store.start();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(store.reactions.value, Reactions.quick);

    final pick = Reactions.quick.last;
    await store.setSlot(0, pick);
    expect(store.reactions.value.first, pick);
    final saved = (await AuthApi.instance.me()).quickReactions!;
    expect(saved.first, pick);
    expect(saved.toSet(), hasLength(Reactions.quick.length),
        reason: 'the two slots swapped, no repeats');

    await store.reset();
    expect((await AuthApi.instance.me()).quickReactions, Reactions.quick);
  }, skip: enabled ? false : 'needs a backend; see the top of the file');
}
