import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/api/local_cache.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';

/// Something the user did that the backend hasn't heard of yet.
class OutboxOp {
  OutboxOp({
    required this.id,
    required this.type,
    required this.chat,
    required this.data,
  });

  factory OutboxOp.fromJson(Map<String, dynamic> json) => OutboxOp(
        id: json['id'] as String,
        type: json['type'] as String,
        chat: json['chat'] as String,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );

  final String id;

  /// One of the `Outbox.*` kinds.
  final String type;
  final String chat;
  Map<String, dynamic> data;

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'chat': chat, 'data': data};
}

/// How an op ended: [sent] is the message the backend made of a send;
/// [error] is set when the backend refused it for good.
class OutboxResult {
  const OutboxResult(this.op, {this.sent, this.error});

  final OutboxOp op;
  final ChatMessage? sent;
  final String? error;
}

/// Everything the user does in chats shows on screen at once and is sent
/// from here: in order, kept on the phone across restarts, and tried again
/// when the internet comes back. Like the outbox of a mail app.
///
/// The backend refusing an op (a 4xx) drops it and reports it in
/// [results]; no connection or a server error keeps it for later.
class Outbox {
  Outbox._();

  static final instance = Outbox._();

  static const sendText = 'send';
  static const sendImage = 'image';
  static const sendVoice = 'voice';
  static const edit = 'edit';
  static const deleteMessage = 'deleteMessage';
  static const react = 'react';
  static const deleteChat = 'deleteChat';

  static const _cacheName = 'outbox';

  final _chats = ChatsApi.instance;

  /// Waiting ops, oldest first.
  final ValueNotifier<List<OutboxOp>> ops = ValueNotifier(const []);

  final _results = StreamController<OutboxResult>.broadcast();
  Stream<OutboxResult> get results => _results.stream;

  bool _flushing = false;
  Timer? _retry;
  int _failures = 0;
  bool _listening = false;
  int _ids = 0;

  /// A new id for a message not sent yet; unique across restarts.
  String newLocalId() =>
      'local-${DateTime.now().microsecondsSinceEpoch}-${_ids++}';

  /// Reads the signed-in account's waiting ops and starts sending them
  /// whenever the live socket is connected.
  Future<void> load() async {
    final saved = await LocalCache.instance.read(_cacheName);
    ops.value = [
      if (saved is List)
        for (final raw in saved)
          if (raw is Map) OutboxOp.fromJson(Map<String, dynamic>.from(raw)),
    ];
    if (!_listening) {
      _listening = true;
      LiveSocket.instance.connected.addListener(() {
        if (LiveSocket.instance.connected.value) flush();
      });
    }
    unawaited(flush());
  }

  /// Forgets every waiting op, with their files; on sign-out.
  Future<void> clear() async {
    _retry?.cancel();
    for (final op in ops.value) {
      await _deleteFile(op);
    }
    ops.value = const [];
  }

  Future<void> add(OutboxOp op) async {
    ops.value = [...ops.value, op];
    await _save();
    unawaited(flush());
  }

  /// Ops waiting for [chat], oldest first.
  List<OutboxOp> forChat(String chat) =>
      [for (final op in ops.value) if (op.chat == chat) op];

  /// Messages of [chat] waiting to be sent, as the chat shows them.
  List<ChatMessage> pendingMessages(String chat, String me) => [
        for (final op in forChat(chat))
          if (op.type == sendText)
            ChatMessage(
              id: op.data['localId'] as String,
              text: (op.data['text'] as String?) ?? '',
              senderId: me,
              senderName: '',
              createdAt: null,
              replyTo: ReplyPreview.fromMap(op.data['replyTo']),
            ),
      ];

  /// Photos and voice messages of [chat] still on their way.
  int pendingUploads(String chat) => forChat(chat)
      .where((op) => op.type == sendImage || op.type == sendVoice)
      .length;

  /// Chats deleted or left here that the backend hasn't heard of yet.
  Set<String> get deletedChats =>
      {for (final op in ops.value) if (op.type == deleteChat) op.chat};

  /// Takes back a message that hasn't gone yet. False when it is being
  /// sent right now (then it is deleted once it arrives).
  Future<bool> cancelSend(String localId) async {
    if (_inFlight?.data['localId'] == localId) return false;
    final before = ops.value.length;
    ops.value = [
      for (final op in ops.value)
        if (op.data['localId'] != localId) op,
    ];
    if (ops.value.length == before) return false;
    await _save();
    return true;
  }

  /// Changes the text of a message that hasn't gone yet.
  Future<bool> editPending(String localId, String text) async {
    for (final op in ops.value) {
      if (op.data['localId'] == localId && op != _inFlight) {
        op.data = {...op.data, 'text': text};
        ops.value = [...ops.value];
        await _save();
        return true;
      }
    }
    return false;
  }

  /// Keeps a photo or recording until it is sent; returns where.
  Future<String> keepFile(Uint8List bytes, String ext) async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/outbox_files');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/${newLocalId()}$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  OutboxOp? _inFlight;

  /// Sends the waiting ops one by one, in order, until one can't go yet.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    _retry?.cancel();
    try {
      while (ops.value.isNotEmpty) {
        final op = ops.value.first;
        _inFlight = op;
        try {
          final sent = await _run(op);
          _done(op);
          _failures = 0;
          _results.add(OutboxResult(op, sent: sent));
        } on ApiException catch (e) {
          if (_isFinal(e)) {
            _done(op);
            _results.add(OutboxResult(op, error: e.message));
          } else {
            _later();
            return;
          }
        } on FileSystemException catch (e) {
          // The photo or recording is gone: it can never be sent.
          _done(op);
          _results.add(OutboxResult(op, error: 'The file is gone: $e'));
        } catch (e) {
          // No connection or a timeout: try again later.
          debugPrint('Outbox: ${op.type} waits: $e');
          _later();
          return;
        } finally {
          _inFlight = null;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// The backend said no for good, as opposed to "not now".
  /// Storage turning an upload down is "not now": the next try gets a
  /// fresh upload link.
  static bool _isFinal(ApiException e) =>
      e.code != 'upload' &&
      e.status >= 400 &&
      e.status < 500 &&
      e.status != 401 &&
      e.status != 408 &&
      e.status != 429;

  void _done(OutboxOp op) {
    ops.value = [for (final o in ops.value) if (o != op) o];
    unawaited(_save());
    unawaited(_deleteFile(op));
  }

  /// Tries again after 2, 4, 8... up to 60 seconds, or as soon as the
  /// socket connects again.
  void _later() {
    _retry?.cancel();
    final seconds = math.min(60, 2 << math.min(_failures, 5));
    _failures++;
    _retry = Timer(Duration(seconds: seconds), flush);
  }

  Future<ChatMessage?> _run(OutboxOp op) async {
    final d = op.data;
    final replyTo = ReplyPreview.fromMap(d['replyTo'])?.messageId;
    switch (op.type) {
      case sendText:
        return _chats.send(op.chat,
            text: (d['text'] as String?) ?? '', replyTo: replyTo);
      case sendImage:
        final bytes = await File(d['path'] as String).readAsBytes();
        final key = await _chats.upload(op.chat,
            kind: 'image',
            contentType: d['contentType'] as String,
            bytes: bytes);
        return _chats.send(op.chat,
            text: (d['caption'] as String?) ?? '',
            imageKey: key,
            imageWidth: d['width'] as int?,
            imageHeight: d['height'] as int?,
            replyTo: replyTo);
      case sendVoice:
        final bytes = await File(d['path'] as String).readAsBytes();
        final key = await _chats.upload(op.chat,
            kind: 'voice', contentType: 'audio/mp4', bytes: bytes);
        return _chats.send(op.chat,
            audioKey: key, audioMs: d['ms'] as int?, replyTo: replyTo);
      case edit:
        await _chats.edit(op.chat, d['id'] as String, d['text'] as String);
      case deleteMessage:
        try {
          await _chats.deleteMessage(op.chat, d['id'] as String);
        } on ApiException catch (e) {
          if (!e.isNotFound) rethrow; // already gone
        }
      case react:
        await _chats.react(op.chat, d['id'] as String, d['emoji'] as String?);
      case deleteChat:
        try {
          var isOwner = d['isOwner'] as bool?;
          isOwner ??= (await _chats.chat(op.chat))['ownerId'] ==
              ApiClient.instance.userId;
          await _chats.deleteOrLeave(op.chat, isOwner: isOwner);
        } on ApiException catch (e) {
          if (!e.isNotFound) rethrow; // already gone
        }
    }
    return null;
  }

  Future<void> _save() => LocalCache.instance
      .write(_cacheName, [for (final op in ops.value) op.toJson()]);

  Future<void> _deleteFile(OutboxOp op) async {
    final path = op.data['path'];
    if (path is! String) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
