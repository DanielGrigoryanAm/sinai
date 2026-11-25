import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Something that happened on the backend: a new message, a reaction, a
/// read mark, typing, someone coming online...
class LiveEvent {
  const LiveEvent(this.type, this.chat, this.data);

  /// Sent by the socket itself after it connected again: whatever happened
  /// meanwhile was missed, so screens should reload.
  static const reconnected = 'socket.reconnected';

  final String type;
  final String? chat;
  final dynamic data;
}

/// The one live connection to the backend. It connects with the current
/// access token, reconnects by itself with growing pauses when the network
/// drops, and hands every event to [events].
class LiveSocket {
  LiveSocket([ApiClient? api]) : _api = api ?? ApiClient.instance;

  static final instance = LiveSocket();

  final ApiClient _api;
  final _events = StreamController<LiveEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  int _failures = 0;
  bool _wanted = false;
  bool _everConnected = false;

  /// Whether the socket is open right now.
  final connected = ValueNotifier<bool>(false);

  Stream<LiveEvent> get events => _events.stream;

  /// Events of one chat.
  Stream<LiveEvent> eventsOf(String chat) =>
      events.where((e) => e.chat == chat || e.type == LiveEvent.reconnected);

  /// Opens the connection and keeps it open until [stop].
  void start() {
    if (_wanted) return;
    _wanted = true;
    _connect();
  }

  /// Closes it, e.g. on sign-out.
  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    await _subscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    connected.value = false;
  }

  /// Tells the others in [chat] that the user is typing.
  void sendTyping(String chat) => _send({'type': 'typing', 'chat': chat});

  void _send(Map<String, String> message) {
    if (connected.value) _channel?.sink.add(jsonEncode(message));
  }

  Future<void> _connect() async {
    if (!_wanted) return;
    final token = await _api.accessToken();
    if (token == null) {
      _scheduleRetry();
      return;
    }
    try {
      final channel = WebSocketChannel.connect(ApiConfig.socketUri(token));
      await channel.ready;
      if (!_wanted) {
        channel.sink.close();
        return;
      }
      _channel = channel;
      _failures = 0;
      connected.value = true;
      if (_everConnected) {
        _events.add(const LiveEvent(LiveEvent.reconnected, null, null));
      }
      _everConnected = true;
      _subscription = channel.stream.listen(
        _onMessage,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Live socket: could not connect: $e');
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      _events.add(LiveEvent(
        json['type'] as String,
        json['chat'] as String?,
        json['data'],
      ));
    } catch (e) {
      debugPrint('Live socket: bad event: $e');
    }
  }

  void _onClosed() {
    connected.value = false;
    _channel = null;
    _scheduleRetry();
  }

  /// Waits 1, 2, 4... up to 30 seconds between tries, with some jitter so
  /// phones don't all come back at the same moment after an outage.
  void _scheduleRetry() {
    if (!_wanted) return;
    _retry?.cancel();
    final seconds = math.min(30, 1 << math.min(_failures, 5));
    _failures++;
    final jitter = math.Random().nextInt(1000);
    _retry = Timer(Duration(seconds: seconds, milliseconds: jitter), _connect);
  }
}
