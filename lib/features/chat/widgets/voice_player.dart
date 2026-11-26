import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:sinai/api/media_url.dart';

/// What the shared voice player is doing right now.
@immutable
class VoicePlayback {
  const VoicePlayback({
    this.url,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  /// Voice message currently loaded, or null when idle.
  final String? url;
  final bool isPlaying;

  /// Downloading the file before playback starts.
  final bool isLoading;
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
      if (playback.value.isLoading) return;
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
      isLoading: current.isLoading,
      position: position ?? current.position,
      duration: duration ?? current.duration,
    );
  }

  /// Plays [url], or pauses/resumes it when it is already the loaded one.
  Future<void> toggle(String url) async {
    final current = playback.value;

    try {
      if (current.url == url && current.isLoading) return;
      if (current.url == url) {
        if (current.isPlaying) {
          await _player.pause();
        } else {
          await _player.resume();
        }
        return;
      }

      await _player.stop();
      playback.value = VoicePlayback(url: url, isLoading: true);
      // Download fully first (cached for replays) so playback starts at
      // the very beginning instead of skipping while it streams.
      // Backend files need the token; cached by their address without it.
      final source = mediaUrl(url);
      final file = await DefaultCacheManager()
          .getSingleFile(source.url, key: source.cacheKey);
      // Another message may have been tapped meanwhile.
      if (playback.value.url != url) return;
      playback.value = VoicePlayback(url: url, isPlaying: true);
      await _player.play(DeviceFileSource(file.path));
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
