import 'package:sinai/api/api_client.dart';

/// Writes a chat's mini game, which lives in the chat's `game` field.
///
/// Starts and moves are stamped with `at`, which is how the others get a
/// notification; picking or putting a game away is not.
abstract final class GameStore {
  static String _path(String chat) => '/v1/chats/${chat.toUpperCase()}';

  /// Replaces the whole game, e.g. a new one starting.
  static Future<void> replace(
    String chat,
    Map<String, dynamic> game, {
    bool stamp = true,
  }) =>
      ApiClient.instance.patch(_path(chat), {
        'game': {
          ...game,
          if (stamp) 'at': DateTime.now().millisecondsSinceEpoch,
        },
      });

  /// Changes some fields of the game on screen, [current], e.g. a move:
  /// the backend gets the whole game with them applied.
  static Future<void> change(
    String chat,
    Map<String, dynamic> current,
    Map<String, dynamic> changes, {
    bool stamp = true,
  }) =>
      ApiClient.instance.patch(_path(chat), {
        'game': {
          ...current,
          ...changes,
          if (stamp) 'at': DateTime.now().millisecondsSinceEpoch,
        },
      });
}
