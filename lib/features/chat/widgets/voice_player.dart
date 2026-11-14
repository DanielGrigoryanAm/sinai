import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// What the shared voice player is doing right now.
@immutable
class VoicePlayback {
  const VoicePlayback({
    this.url,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  /// Voice message currently loaded, or null when idle.
  final String? url;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
}

/// Plays voice messages. A single shared player, so starting one message
/// stops whichever was playing before.
class VoicePlayer {
  VoicePlayer._() {
    _player.onPositionChanged.listen((position) {
      _update(position: position);
    });
    _player.onDurationChanged.listen((duration) {
      _update(duration: duration);
    });
    _player.onPlayerStateChanged.listen((state) {
      _update(isPlaying: state == PlayerState.playing);
    });
    _player.onPlayerComplete.listen((_) {
      playback.value = const VoicePlayback();
    });
  }

  static final VoicePlayer instance = VoicePlayer._();

  final AudioPlayer _player = AudioPlayer();

  final ValueNotifier<VoicePlayback> playback =
      ValueNotifier(const VoicePlayback());

  void _update({bool? isPlaying, Duration? position, Duration? duration}) {
    final current = playback.value;
    if (current.url == null) return;
    playback.value = VoicePlayback(
      url: current.url,
      isPlaying: isPlaying ?? current.isPlaying,
      position: position ?? current.position,
      duration: duration ?? current.duration,
    );
  }

  /// Plays [url], or pauses/resumes it when it is already the loaded one.
  Future<void> toggle(String url) async {
    final current = playback.value;

    try {
      if (current.url == url) {
        if (current.isPlaying) {
          await _player.pause();
        } else {
          await _player.resume();
        }
        return;
      }

      await _player.stop();
      playback.value = VoicePlayback(url: url);
      await _player.play(UrlSource(url));
    } catch (_) {
      playback.value = const VoicePlayback();
      rethrow;
    }
  }

  /// Stops playback, e.g. when the chat screen is closed.
  Future<void> stop() async {
    playback.value = const VoicePlayback();
    await _player.stop();
  }
}
