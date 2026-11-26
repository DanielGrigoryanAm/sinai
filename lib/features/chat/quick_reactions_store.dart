import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/current_user.dart';

/// The user's own set of quick reactions, shown in the message menu and the
/// drag strip. Stored with the account, so it follows the user: on the
/// backend's profile, or in `users/{uid}.quickReactions` in Firestore.
class QuickReactionsStore {
  QuickReactionsStore._();

  static final QuickReactionsStore instance = QuickReactionsStore._();

  /// Always exactly [Reactions.quick].length distinct emoji.
  final ValueNotifier<List<String>> reactions =
      ValueNotifier(List.unmodifiable(Reactions.quick));

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  String? _uid;

  /// The reaction a double tap leaves: the first one in the set.
  String get like => reactions.value.first;

  DocumentReference<Map<String, dynamic>>? get _doc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Starts following the saved set. Safe to call repeatedly.
  void start() {
    if (ApiConfig.useBackend) {
      _startBackend();
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid == _uid) return;
    _uid = uid;
    _subscription?.cancel();
    _subscription = _doc!.snapshots().listen(
      (snapshot) {
        final saved = _parse(snapshot.data()?['quickReactions']);
        if (saved != null && !listEquals(saved, reactions.value)) {
          reactions.value = saved;
        }
      },
      onError: (Object e) => debugPrint('Quick reactions unavailable: $e'),
    );
  }

  Future<void> _startBackend() async {
    final uid = currentUserId();
    if (uid == null || uid == _uid) return;
    _uid = uid;
    try {
      final saved = _parse((await AuthApi.instance.me()).quickReactions);
      if (saved != null && !listEquals(saved, reactions.value)) {
        reactions.value = saved;
      }
    } catch (e) {
      // Retried on the next chat opened.
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
      if (ApiConfig.useBackend) {
        await AuthApi.instance.setQuickReactions(list);
        return;
      }
      await _doc?.set({'quickReactions': list}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Saving quick reactions failed: $e');
    }
  }
}
