import 'dart:async';

import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/live_socket.dart';

/// A chat as the info sheet and the chat header show it, kept current by
/// the live socket: renames, new photos, members coming and going, and
/// members going online or offline.
///
/// Shaped like the Firebase chat document (`name`, `ownerId`, `photoUrl`,
/// `participantIds`, `game`) so screens read it the same way, plus
/// `members`: user id → `{name, online, lastSeen}`.
Stream<Map<String, dynamic>?> watchChat(String code) {
  final api = ApiClient.instance;
  final chat = code.toUpperCase();
  late StreamController<Map<String, dynamic>?> out;
  StreamSubscription<LiveEvent>? live;
  Map<String, dynamic>? current;

  void show(Map<String, dynamic> raw) {
    current = _shape(raw);
    if (!out.isClosed) out.add(current);
  }

  Future<void> load() async {
    try {
      show(await api.get('/v1/chats/$chat') as Map<String, dynamic>);
    } on ApiException catch (e) {
      // Removed from the chat, or it was deleted.
      if (e.isNotFound && !out.isClosed) out.add(null);
    } catch (_) {
      // Keeps what it has; the next event or reconnect tries again.
    }
  }

  out = StreamController<Map<String, dynamic>?>(
    onListen: () {
      load();
      live = LiveSocket.instance.events.listen((e) {
        if (e.type == LiveEvent.reconnected) {
          load();
        } else if (e.type == 'chat.updated' && e.chat == chat) {
          show(e.data as Map<String, dynamic>);
        } else if ((e.type == 'chat.removed' || e.type == 'chat.deleted') &&
            e.chat == chat) {
          out.add(null);
        } else if (e.type == 'presence' && current != null) {
          _presence(current!, e.data as Map<String, dynamic>);
          out.add(current);
        }
      });
    },
    onCancel: () => live?.cancel(),
  );
  return out.stream;
}

Map<String, dynamic> _shape(Map<String, dynamic> raw) {
  final members = <String, Map<String, dynamic>>{};
  for (final m in (raw['members'] as List? ?? const [])) {
    members[m['userId'] as String] = {
      'name': ((m['name'] as String?) ?? '').trim(),
      'online': m['online'] == true,
      'lastSeen': DateTime.tryParse('${m['lastSeen']}')?.toLocal(),
    };
  }
  return {
    'name': raw['name'],
    'ownerId': raw['ownerId'],
    'photoUrl': ChatsApi.fileUrl(raw['photoUrl']),
    'game': raw['game'],
    'watch': raw['watch'],
    // The server's clock and ours when this arrived, to read the server's
    // clock later (see WatchState).
    'serverTime': raw['serverTime'],
    'receivedAt': DateTime.now().millisecondsSinceEpoch,
    'participantIds': members.keys.toList(),
    'members': members,
  };
}

/// Applies a member going online or offline.
void _presence(Map<String, dynamic> chat, Map<String, dynamic> data) {
  final member =
      (chat['members'] as Map<String, Map<String, dynamic>>)[data['userId']];
  if (member == null) return;
  member['online'] = data['online'] == true;
  final lastSeen = DateTime.tryParse('${data['lastSeen']}');
  if (lastSeen != null) member['lastSeen'] = lastSeen.toLocal();
}
