import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';

/// Writes a chat's mini game, which lives in the chat's `game` field: in
/// Firestore, or on the backend when the app runs on it.
///
/// Starts and moves are stamped with `at`, which is how the others get a
/// notification; picking or putting a game away is not.
abstract final class GameStore {
  static DocumentReference<Map<String, dynamic>> _doc(String chat) =>
      FirebaseFirestore.instance.collection('chats').doc(chat);

  static String _path(String chat) => '/v1/chats/${chat.toUpperCase()}';

  /// Replaces the whole game, e.g. a new one starting.
  static Future<void> replace(
    String chat,
    Map<String, dynamic> game, {
    bool stamp = true,
  }) {
    if (ApiConfig.useBackend) {
      return ApiClient.instance.patch(_path(chat), {
        'game': {
          ...game,
          if (stamp) 'at': DateTime.now().millisecondsSinceEpoch,
        },
      });
    }
    return _doc(chat).update({
      'game': {
        ...game,
        if (stamp) 'at': FieldValue.serverTimestamp(),
      },
    });
  }

  /// Changes some fields of the game on screen, [current], e.g. a move.
  /// Firestore changes just those fields; the backend gets the whole game
  /// with them applied.
  static Future<void> change(
    String chat,
    Map<String, dynamic> current,
    Map<String, dynamic> changes, {
    bool stamp = true,
  }) {
    if (ApiConfig.useBackend) {
      return ApiClient.instance.patch(_path(chat), {
        'game': {
          ...current,
          ...changes,
          if (stamp) 'at': DateTime.now().millisecondsSinceEpoch,
        },
      });
    }
    return _doc(chat).update({
      for (final e in changes.entries) 'game.${e.key}': e.value,
      if (stamp) 'game.at': FieldValue.serverTimestamp(),
    });
  }
}
