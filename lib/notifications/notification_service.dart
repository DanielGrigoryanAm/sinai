import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';

/// Registers this device for push notifications and opens the right chat
/// when the user taps one.
///
/// The device token goes to the backend (`PUT /v1/devices`), or to
/// `users/{uid}.fcmTokens` in Firestore for the Firebase app's Cloud
/// Functions.
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

  /// Points this phone's notifications at the signed-in account, e.g.
  /// after switching to another account by phone number.
  Future<void> addTokenToCurrentUser() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('Could not attach the push token: $e');
    }
  }

  /// Stops this phone from getting the signed-in account's notifications.
  /// Called before signing in to another account, while the current one
  /// may still be edited.
  Future<void> removeTokenFromCurrentUser() async {
    if (ApiConfig.useBackend) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await ApiClient.instance
              .delete('/v1/devices/${Uri.encodeComponent(token)}');
        }
      } catch (e) {
        debugPrint('Could not detach the push token: $e');
      }
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmTokens': FieldValue.arrayRemove([token])
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Could not detach the push token: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    if (ApiConfig.useBackend) {
      try {
        await ApiClient.instance.put('/v1/devices', {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
        });
      } catch (e) {
        debugPrint('Could not save the push token: $e');
      }
      return;
    }
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
