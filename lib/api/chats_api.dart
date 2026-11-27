import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/local_cache.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';

/// Someone found by their personal code.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.code,
    this.photoUrl,
  });

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        name: ((json['name'] as String?) ?? '').trim(),
        code: json['code'] as String,
        photoUrl: ChatsApi.fileUrl(json['photoUrl']),
      );

  final String id;
  final String name;
  final String code;
  final String? photoUrl;
}

/// Chats and messages on the backend, turned into the app's models.
class ChatsApi {
  ChatsApi([ApiClient? client]) : _api = client ?? ApiClient.instance;

  static final instance = ChatsApi();

  final ApiClient _api;

  static String _chat(String code) => '/v1/chats/${code.toUpperCase()}';

  // Chats

  Future<List<ChatSummary>> chats() async {
    final list = await _api.get('/v1/chats') as List;
    // Kept as the backend sent it, for the next start (see cachedChats).
    unawaited(LocalCache.instance.write(_chatsCache, list));
    return _summaries(list);
  }

  static const _chatsCache = 'chats';
  static String _messagesCache(String code) =>
      'messages_${code.toUpperCase()}';

  List<ChatSummary> _summaries(List list) {
    final me = _api.userId;
    return [
      for (final raw in list) _summary(raw as Map<String, dynamic>, me),
    ];
  }

  /// The chats list as last loaded; null when there is none on this phone.
  Future<List<ChatSummary>?> cachedChats() async {
    final list = await LocalCache.instance.read(_chatsCache);
    if (list is! List) return null;
    try {
      return _summaries(list);
    } catch (_) {
      return null;
    }
  }

  /// Takes a chat out of the cached list at once (deleted or left), so it
  /// doesn't come back on the next start before the backend has heard.
  Future<void> forgetCachedChat(String code) async {
    final list = await LocalCache.instance.read(_chatsCache);
    if (list is List) {
      await LocalCache.instance.write(_chatsCache, [
        for (final c in list)
          if (c is Map && c['code'] != code.toUpperCase()) c,
      ]);
    }
    await LocalCache.instance.remove(_messagesCache(code));
  }

  /// A chat's newest messages as last shown, oldest first.
  Future<List<ChatMessage>?> cachedMessages(String code) async {
    final list = await LocalCache.instance.read(_messagesCache(code));
    if (list is! List) return null;
    try {
      return [for (final raw in list) message(raw as Map<String, dynamic>)];
    } catch (_) {
      return null;
    }
  }

  /// Keeps up to the newest [keep] of [messages] for the next opening.
  Future<void> cacheMessages(
    String code,
    List<ChatMessage> messages, {
    int keep = 60,
  }) {
    final sent = [for (final m in messages) if (!m.isLocal) m];
    final newest = sent.length > keep ? sent.sublist(sent.length - keep) : sent;
    return LocalCache.instance.write(
      _messagesCache(code),
      [for (final m in newest) m.toJson()],
    );
  }

  /// Creates a chat; returns its code.
  Future<String> create(String name) async {
    final chat = await _api.post('/v1/chats', {'name': name}) as Map;
    return chat['code'] as String;
  }

  Future<void> join(String code) => _api.post('${_chat(code)}/join');

  /// The person with this personal code; throws [ApiException] 404 when
  /// there is no one.
  Future<Person> person(String code) async => Person.fromJson(await _api
      .get('/v1/users/${Uri.encodeComponent(code.trim().toUpperCase())}')
      as Map<String, dynamic>);

  /// Opens the one-to-one chat with the person with this personal code
  /// (making it the first time); returns its code.
  Future<String> openDirect(String personCode) async {
    final chat = await _api.post('/v1/chats/direct', {'code': personCode})
        as Map<String, dynamic>;
    return chat['code'] as String;
  }

  /// The chat with its members and their read marks.
  Future<Map<String, dynamic>> chat(String code) async =>
      await _api.get(_chat(code)) as Map<String, dynamic>;

  /// Owners delete the chat for everyone; others leave it.
  Future<void> deleteOrLeave(String code, {required bool isOwner}) => isOwner
      ? _api.delete(_chat(code))
      : _api.delete('${_chat(code)}/members/me');

  Future<void> markRead(String code) => _api.post('${_chat(code)}/read');

  /// Owner only.
  Future<void> rename(String code, String name) =>
      _api.patch(_chat(code), {'name': name});

  /// Owner only: uploads [bytes] and makes them the chat's picture.
  Future<void> setPhoto(String code, Uint8List bytes, String contentType) async {
    final key = await upload(code,
        kind: 'avatar', contentType: contentType, bytes: bytes);
    await _api.patch(_chat(code), {'photoUrl': key});
  }

  /// Owner only: takes a member out of the chat.
  Future<void> removeMember(String code, String userId) =>
      _api.delete('${_chat(code)}/members/$userId');

  // Messages

  /// Up to [limit] messages older than [before] (newest ones if null),
  /// oldest first.
  Future<List<ChatMessage>> messages(
    String code, {
    String? before,
    int limit = 30,
  }) async {
    final list = await _api.get('${_chat(code)}/messages', {
      'limit': '$limit',
      if (before != null) 'before': before,
    }) as List;
    return [
      for (final raw in list.reversed) message(raw as Map<String, dynamic>),
    ];
  }

  Future<ChatMessage> send(
    String code, {
    String text = '',
    String? replyTo,
    String? imageKey,
    int? imageWidth,
    int? imageHeight,
    String? audioKey,
    int? audioMs,
    String? forwardedFrom,
    String? clientId,
  }) async =>
      message(await _api.post('${_chat(code)}/messages', {
        'text': text,
        // The app's own id: sending it again returns the same message.
        if (clientId != null) 'clientId': clientId,
        if (replyTo != null) 'replyTo': replyTo,
        if (imageKey != null) 'imageUrl': imageKey,
        if (imageWidth != null) 'imageWidth': imageWidth,
        if (imageHeight != null) 'imageHeight': imageHeight,
        if (audioKey != null) 'audioUrl': audioKey,
        if (audioMs != null) 'audioMs': audioMs,
        if (forwardedFrom != null) 'forwardedFrom': forwardedFrom,
      }) as Map<String, dynamic>);

  /// The chat's photos (`image`) or voice messages (`voice`), newest
  /// first.
  Future<List<ChatMessage>> media(String code, String kind) async {
    final list = await _api.get(
        '${_chat(code)}/media', {'kind': kind, 'limit': '300'}) as List;
    return [for (final raw in list) message(raw as Map<String, dynamic>)];
  }

  /// Messages whose text contains [query], newest first.
  Future<List<ChatMessage>> search(String code, String query) async {
    final list = await _api.get('${_chat(code)}/messages/search',
        {'q': query, 'limit': '100'}) as List;
    return [for (final raw in list) message(raw as Map<String, dynamic>)];
  }

  /// Copies a message of [fromChat] into [toChat], its file included.
  Future<void> forward({
    required String fromChat,
    required String messageId,
    required String toChat,
  }) =>
      _api.post('${_chat(toChat)}/forward', {
        'chat': fromChat.toUpperCase(),
        'messageId': messageId,
      });

  Future<void> edit(String code, String id, String text) =>
      _api.patch('${_chat(code)}/messages/$id', {'text': text});

  Future<void> deleteMessage(String code, String id) =>
      _api.delete('${_chat(code)}/messages/$id');

  /// Sets the user's reaction, or clears it when [emoji] is null.
  Future<void> react(String code, String id, String? emoji) => emoji == null
      ? _api.delete('${_chat(code)}/messages/$id/reaction')
      : _api.put('${_chat(code)}/messages/$id/reaction', {'emoji': emoji});

  /// Uploads a photo, voice message or chat picture straight to storage
  /// and returns its key, to send in a message or set as the chat photo.
  Future<String> upload(
    String code, {
    required String kind,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final upload = await _api.post('${_chat(code)}/uploads', {
      'kind': kind,
      'contentType': contentType,
    }) as Map;
    final response = await http.put(
      Uri.parse(upload['uploadUrl'] as String),
      headers: {'Content-Type': contentType},
      body: bytes,
    );
    if (response.statusCode >= 300) {
      throw ApiException(response.statusCode, 'upload', 'Upload failed');
    }
    return upload['key'] as String;
  }

  // Models

  /// A stored file's address as the app loads it.
  static String? fileUrl(Object? path) {
    if (path is! String || path.isEmpty) return null;
    return path.startsWith('http') ? path : '${ApiConfig.baseUrl}$path';
  }

  static ChatMessage message(Map<String, dynamic> m) {
    final reply = m['replyTo'];
    return ChatMessage(
      id: m['id'] as String,
      text: (m['text'] as String?) ?? '',
      senderId: (m['senderId'] as String?) ?? '',
      senderName: (m['senderName'] as String?) ?? 'Guest',
      createdAt: DateTime.tryParse('${m['createdAt']}')?.toLocal(),
      imageUrl: fileUrl(m['imageUrl']),
      imageWidth: (m['imageWidth'] as num?)?.toInt(),
      imageHeight: (m['imageHeight'] as num?)?.toInt(),
      audioUrl: fileUrl(m['audioUrl']),
      audioDurationMs: (m['audioMs'] as num?)?.toInt(),
      reactions: {
        if (m['reactions'] case final Map reactions)
          for (final e in reactions.entries) e.key as String: '${e.value}',
      },
      replyTo: reply is Map
          ? ReplyPreview(
              messageId: reply['id'] as String,
              senderName: (reply['senderName'] as String?) ?? '',
              text: _preview(reply['text'] as String?, reply['kind'] as String?),
            )
          : null,
      isEdited: m['editedAt'] != null,
      forwardedFrom: m['forwardedFrom'] as String?,
      clientId: m['clientId'] as String?,
    );
  }

  static String _preview(String? text, String? kind) {
    if (text != null && text.isNotEmpty) return text;
    return switch (kind) {
      'image' => 'Photo',
      'voice' => 'Voice message',
      _ => '',
    };
  }

  static ChatSummary _summary(Map<String, dynamic> c, String? me) {
    final last = c['lastMessage'] as Map<String, dynamic>?;
    final direct = c['direct'] == true;
    final peer = c['peer'] as Map<String, dynamic>?;
    // A direct chat is called after the other person.
    final rawName = direct ? (peer?['name']) : c['name'];
    final name = ((rawName as String?) ?? '').trim();
    final unread = (c['unread'] as num?)?.toInt() ?? 0;
    final lastAt = DateTime.tryParse('${last?['createdAt']}')?.toLocal();
    return ChatSummary(
      code: c['code'] as String,
      name: name.isEmpty ? null : name,
      isOwner: c['ownerId'] == me,
      photoUrl: fileUrl(direct ? (peer?['photoUrl']) : c['photoUrl']),
      direct: direct,
      lastMessage: last == null
          ? null
          : _preview(last['text'] as String?, last['kind'] as String?),
      lastSenderId: last?['senderId'] as String?,
      lastSenderName: last?['senderName'] as String?,
      lastActivityAt:
          lastAt ?? DateTime.tryParse('${c['createdAt']}')?.toLocal(),
      hasUnread: unread > 0,
      unreadCount: unread,
    );
  }
}
