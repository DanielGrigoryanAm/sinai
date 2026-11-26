import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:sinai/features/presence/presence_service.dart';
import 'package:sinai/features/presence/realtime_db.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/api/live_socket.dart';

/// The line under a chat's title: who is typing, or whether the other
/// person is online, or how many members are online.
@immutable
class ChatStatus {
  const ChatStatus(this.text, {this.active = false, this.typing = false});

  final String text;

  /// Someone is typing.
  final bool typing;

  /// Typing or online; shown in the accent color.
  final bool active;
}

/// Follows a chat's typing marks and its members' presence and turns them
/// into a [ChatStatus].
class ChatStatusController {
  ChatStatusController(this.chatCode) {
    // Typing and "online" expire with time, not only with new data.
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) => _update());
    if (ApiConfig.useBackend) {
      _watchBackend();
      return;
    }
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatCode)
        .snapshots()
        .listen(_onChat, onError: (Object _) {});
    _typingSubscription = RealtimeDb.typing(chatCode)
        .onValue
        .listen(_onTyping, onError: (Object _) {});
  }

  /// On the backend the live chat view brings members with their online
  /// status, and the socket brings typing marks.
  void _watchBackend() {
    _chatSubscription = watchChat(chatCode).listen((data) {
      if (data == null) return;
      final members = data['members'] as Map<String, Map<String, dynamic>>;
      final others = members.keys.where((uid) => uid != _me).toList();
      if (!_sameMembers(others)) _others = others;
      _presence
        ..clear()
        ..addAll({
          for (final uid in others)
            uid: Presence(
              online: members[uid]!['online'] == true,
              lastSeen: members[uid]!['lastSeen'] as DateTime?,
              name: members[uid]!['name'] as String?,
            ),
        });
      _update();
    });
    _typingSubscription = LiveSocket.instance.eventsOf(chatCode).listen((e) {
      final data = e.data is Map ? e.data as Map : const {};
      final uid = data['userId'] ?? data['senderId'];
      if (uid is! String || uid == _me) return;
      switch (e.type) {
        case 'typing':
          final name = data['name'] as String?;
          _typing[uid] = (
            name: name == null || name.isEmpty ? 'Someone' : name,
            stamp: null,
            seenAt: DateTime.now(),
          );
        // Stopped typing, or sent what they typed.
        case 'typing.stop' || 'message.created':
          _typing.remove(uid);
        default:
          return;
      }
      _update();
    });
  }

  /// A typing mark counts while it was refreshed this recently. Measured
  /// on this phone's clock from when the mark changed, so the two phones'
  /// clocks need not agree.
  static const typingWindow = Duration(seconds: 9);

  final String chatCode;
  final ValueNotifier<ChatStatus?> status = ValueNotifier(null);

  StreamSubscription? _chatSubscription;
  StreamSubscription? _typingSubscription;
  final List<StreamSubscription> _presenceSubscriptions = [];
  Timer? _ticker;

  List<String> _others = const [];
  final Map<String, Presence> _presence = {};

  /// Typing user id → (name, when the mark last changed on this phone).
  final Map<String, ({String name, Object? stamp, DateTime seenAt})> _typing =
      {};

  String? get _me => currentUserId();

  void _onChat(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) return;

    final others = ((data['participantIds'] as List?) ?? const [])
        .whereType<String>()
        .where((uid) => uid != _me)
        .toList();
    if (!_sameMembers(others)) {
      _others = others;
      _watchPresence();
    }

    _update();
  }

  void _onTyping(DatabaseEvent event) {
    final now = DateTime.now();
    final raw = event.snapshot.value;
    final typing = raw is Map ? raw : const {};
    _typing.removeWhere((uid, _) => !typing.containsKey(uid));
    for (final entry in typing.entries) {
      final uid = entry.key;
      final value = entry.value;
      if (uid is! String || uid == _me || value is! Map) continue;
      final stamp = value['at'];
      final previous = _typing[uid];
      // A new stamp means the person is still typing.
      if (previous == null || previous.stamp != stamp) {
        _typing[uid] = (
          name: (value['name'] as String?) ?? 'Someone',
          stamp: stamp,
          seenAt: now,
        );
      }
    }
    _update();
  }

  bool _sameMembers(List<String> others) =>
      others.length == _others.length && others.toSet().containsAll(_others);

  void _watchPresence() {
    for (final subscription in _presenceSubscriptions) {
      subscription.cancel();
    }
    _presenceSubscriptions.clear();
    _presence.removeWhere((uid, _) => !_others.contains(uid));

    for (final uid in _others) {
      _presenceSubscriptions.add(
        RealtimeDb.presence(uid).onValue.listen(
          (event) {
            _presence[uid] = Presence.fromValue(event.snapshot.value);
            _update();
          },
          onError: (Object _) {},
        ),
      );
    }
  }

  void _update() {
    status.value = _compute();
  }

  ChatStatus? _compute() {
    final now = DateTime.now();
    final typingNames = [
      for (final mark in _typing.values)
        if (now.difference(mark.seenAt) < typingWindow) mark.name,
    ];
    if (typingNames.length == 1) {
      return ChatStatus(
        _others.length == 1 ? 'typing…' : '${typingNames.first} is typing…',
        active: true,
        typing: true,
      );
    }
    if (typingNames.length > 1) {
      return ChatStatus('${typingNames.length} people are typing…',
          active: true, typing: true);
    }

    if (_others.isEmpty) return const ChatStatus('only you');

    if (_others.length == 1) {
      final presence = _presence[_others.first];
      if (presence == null) return null;
      if (presence.online) return const ChatStatus('online', active: true);
      final lastSeen = presence.lastSeen;
      return lastSeen == null ? null : ChatStatus(lastSeenText(lastSeen));
    }

    final members = _others.length + 1;
    final online = _others.where((uid) => _presence[uid]?.online ?? false);
    return online.isEmpty
        ? ChatStatus('$members members')
        : ChatStatus('$members members, ${online.length} online');
  }

  /// "last seen just now", "… 5 min ago", "… today at 14:05",
  /// "… yesterday at 09:10" or "… on 3 Nov".
  static String lastSeenText(DateTime lastSeen) {
    final now = DateTime.now();
    final ago = now.difference(lastSeen);
    if (ago < const Duration(minutes: 1)) return 'last seen just now';
    if (ago < const Duration(hours: 1)) {
      return 'last seen ${ago.inMinutes} min ago';
    }

    String time(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    final days = today.difference(day).inDays;
    if (days == 0) return 'last seen today at ${time(lastSeen)}';
    if (days == 1) return 'last seen yesterday at ${time(lastSeen)}';

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final date = '${lastSeen.day} ${months[lastSeen.month - 1]}';
    return lastSeen.year == now.year
        ? 'last seen on $date'
        : 'last seen on $date ${lastSeen.year}';
  }

  void dispose() {
    _chatSubscription?.cancel();
    _typingSubscription?.cancel();
    for (final subscription in _presenceSubscriptions) {
      subscription.cancel();
    }
    _ticker?.cancel();
    status.dispose();
  }
}
