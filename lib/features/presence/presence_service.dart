import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:sinai/features/presence/realtime_db.dart';

/// Tells others whether the user is online and when they were last seen,
/// in `presence/{uid}` of the Realtime Database.
///
/// While the app is in the foreground and connected the user is online.
/// Going to the background marks them offline, and so does the server
/// itself (onDisconnect) when the app is killed or loses its connection.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  StreamSubscription<DatabaseEvent>? _connection;
  bool _started = false;
  bool _foreground = true;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    // Fires on every (re)connection; set up the offline fallback first,
    // then go online, so a dropped connection is always cleaned up.
    _connection = RealtimeDb.instance
        .ref('.info/connected')
        .onValue
        .listen((event) async {
      if (event.snapshot.value != true) return;
      final ref = _ref;
      if (ref == null) return;
      try {
        await ref.onDisconnect().set(_offline);
        if (_foreground) await ref.set(_online);
      } catch (e) {
        debugPrint('Presence setup failed: $e');
      }
    });
  }

  DatabaseReference? get _ref {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : RealtimeDb.presence(uid);
  }

  static final Map<String, Object> _online = {
    'online': true,
    'lastSeen': ServerValue.timestamp,
  };

  static final Map<String, Object> _offline = {
    'online': false,
    'lastSeen': ServerValue.timestamp,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _ref?.set(_online).catchError((Object _) {});
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _foreground = false;
        _ref?.set(_offline).catchError((Object _) {});
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    _connection?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Another user's presence as read from `presence/{uid}`.
class Presence {
  const Presence({required this.online, required this.lastSeen});

  factory Presence.fromValue(Object? value) {
    if (value is! Map) return const Presence(online: false, lastSeen: null);
    final millis = value['lastSeen'];
    return Presence(
      online: value['online'] == true,
      lastSeen:
          millis is int ? DateTime.fromMillisecondsSinceEpoch(millis) : null,
    );
  }

  final bool online;
  final DateTime? lastSeen;
}
