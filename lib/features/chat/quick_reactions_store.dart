import 'package:flutter/foundation.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';

/// The user's own set of quick reactions, shown in the message menu and the
/// drag strip. Kept on the backend profile, so it follows the account.
class QuickReactionsStore {
  QuickReactionsStore._();

  static final QuickReactionsStore instance = QuickReactionsStore._();

  /// Always exactly [Reactions.quick].length distinct emoji.
  final ValueNotifier<List<String>> reactions =
      ValueNotifier(List.unmodifiable(Reactions.quick));

  String? _uid;

  /// The reaction a double tap leaves: the first one in the set.
  String get like => reactions.value.first;

  /// Loads the saved set, once per account. Safe to call repeatedly.
  Future<void> start() async {
    final uid = currentUserId();
    if (uid == null || uid == _uid) return;
    _uid = uid;
    // The saved profile's set at once; the backend's below.
    final cached = _parse(AuthApi.instance.current.value?.quickReactions);
    if (cached != null && !listEquals(cached, reactions.value)) {
      reactions.value = cached;
    }
    try {
      final saved = _parse((await AuthApi.instance.me()).quickReactions);
      if (saved != null && !listEquals(saved, reactions.value)) {
        reactions.value = saved;
      }
    } catch (e) {
      // Tried again on the next chat opened.
      _uid = null;
      debugPrint('Quick reactions unavailable: $e');
    }
  }

  /// A saved set is used only when it is complete and has no repeats.
  static List<String>? _parse(Object? value) {
    if (value is! List || value.length != Reactions.quick.length) return null;
    final list = value.whereType<String>().toList();
    if (list.length != value.length || list.toSet().length != list.length) {
      return null;
    }
    return List.unmodifiable(list);
  }

  /// Puts [emoji] into slot [index]. If it is already in another slot, the
  /// two swap, so the set never holds the same emoji twice.
  Future<void> setSlot(int index, String emoji) async {
    final list = [...reactions.value];
    final existing = list.indexOf(emoji);
    if (existing == index) return;
    if (existing >= 0) list[existing] = list[index];
    list[index] = emoji;
    await _save(list);
  }

  Future<void> reset() => _save(Reactions.quick);

  Future<void> _save(List<String> list) async {
    // Shown at once; the write catches up in the background.
    reactions.value = List.unmodifiable(list);
    try {
      await AuthApi.instance.setQuickReactions(list);
    } catch (e) {
      debugPrint('Saving quick reactions failed: $e');
    }
  }
}
