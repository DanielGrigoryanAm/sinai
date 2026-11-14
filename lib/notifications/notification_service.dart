import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Registers this device for push notifications and opens the right chat
/// when the user taps one.
///
/// The device token is stored in `users/{uid}.fcmTokens`; the
/// `notifyNewMessage` Cloud Function reads it to deliver pushes.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Called with the chat code (and name, when known) of a tapped
  /// notification.
  void Function(String chatCode, String? chatName)? onOpenChat;

  bool _initialized = false;

  /// Safe to call repeatedly; only the first call does the work. Never
  /// throws: the app must keep working without notifications.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // Shows the system permission prompt on Android 13+ and iOS.
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await messaging.getToken();
      if (token != null) await _saveToken(token);
      messaging.onTokenRefresh.listen(_saveToken);

      // Tapped while the app was in the background.
      FirebaseMessaging.onMessageOpenedApp.listen(_openChatFrom);

      // Tapped while the app was closed, which is what launched it.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _openChatFrom(initial);
    } catch (e) {
      debugPrint('Push notifications are unavailable: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayUnion([token]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Could not save the push token: $e');
    }
  }

  void _openChatFrom(RemoteMessage message) {
    final chatCode = message.data['chatCode'];
    if (chatCode is! String || chatCode.isEmpty) return;

    final chatName = message.data['chatName'];
    onOpenChat?.call(
      chatCode,
      chatName is String && chatName.isNotEmpty ? chatName : null,
    );
  }
}
