import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/chat/widgets/voice_player.dart';
import 'package:sinai/theme/color_theme.dart';

/// Small live bits the notch shows even folded into a droplet: the voice
/// message playing and someone typing.
class NotchExtras extends StatelessWidget {
  const NotchExtras({super.key, required this.status, required this.folded});

  final ValueListenable<ChatStatus?> status;

  /// The notch is a droplet, so the name and status line aren't visible.
  final bool folded;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<VoicePlayback>(
            valueListenable: VoicePlayer.instance.playback,
            builder: (context, playback, _) {
              final url = playback.url;
              if (url == null || !(playback.isPlaying || playback.isLoading)) {
                return const SizedBox.shrink();
              }
              return _MiniPlayer(playback: playback, url: url);
            },
          ),
          // The status line says it when the notch is open.
          if (folded)
            ValueListenableBuilder<ChatStatus?>(
              valueListenable: status,
              builder: (context, status, _) => status?.typing ?? false
                  ? const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 2),
                      child: _TypingDots(),
                    )
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.playback, required this.url});

  final VoicePlayback playback;
  final String url;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final left = playback.duration - playback.position;
    final seconds = left.isNegative ? 0 : left.inSeconds;
    return GestureDetector(
      // Pauses; the message's own button carries on from there.
      onTap: () => VoicePlayer.instance.toggle(url).catchError((_) {}),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colors.secondary,
                shape: BoxShape.circle,
              ),
              child: playback.isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(AppIcons.pause, size: 11, color: Colors.white),
            ),
            _Wave(color: colors.secondary, playing: playback.isPlaying),
            Text(
              '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bars bouncing like a sound wave.
class _Wave extends StatefulWidget {
  const _Wave({required this.color, required this.playing});

  final Color color;
  final bool playing;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _beat,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        spacing: 2.5,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 3,
              height: widget.playing
                  ? 5 +
                      11 *
                          (0.5 +
                              0.5 *
                                  math.sin(
                                    _beat.value * 2 * math.pi + i * 1.3,
                                  ))
                  : 5,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

/// Three dots rising one after another.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colorTheme.secondary;
    return AnimatedBuilder(
      animation: _beat,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(
                0,
                -3 *
                    math.max(
                      0,
                      math.sin((_beat.value - i * 0.18) * 2 * math.pi),
                    ),
              ),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}
