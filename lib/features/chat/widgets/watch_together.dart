import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/toast.dart';
import 'package:flutter/services.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// The YouTube video id in a link or text, if any.
String? youtubeId(String text) {
  final match = RegExp(
    r'(?:youtube\.com/(?:watch\?(?:\S*&)?v=|shorts/|live/|embed/)|youtu\.be/)'
    r'([A-Za-z0-9_-]{11})',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(1);
}

/// What a chat is watching together: a video, whether it plays, and where
/// it was at a moment of the server's clock. Everyone's player follows it.
class WatchState {
  const WatchState({
    required this.videoId,
    required this.playing,
    required this.position,
    required this.at,
    required this.serverOffset,
  });

  final String videoId;
  final bool playing;

  /// Seconds into the video at [at].
  final double position;

  /// The server's clock (ms) when [position] was taken.
  final int at;

  /// Server clock minus this phone's, so a wrong phone clock doesn't
  /// throw the video off.
  final int serverOffset;

  static WatchState? fromChat(Map<String, dynamic>? chat) {
    final watch = chat?['watch'];
    if (watch is! Map) return null;
    final videoId = watch['videoId'];
    if (videoId is! String || videoId.isEmpty) return null;
    final serverTime = (chat!['serverTime'] as num?)?.toInt();
    final receivedAt = (chat['receivedAt'] as num?)?.toInt();
    return WatchState(
      videoId: videoId,
      playing: watch['playing'] == true,
      position: (watch['position'] as num?)?.toDouble() ?? 0,
      at: (watch['at'] as num?)?.toInt() ?? 0,
      serverOffset: serverTime == null || receivedAt == null
          ? 0
          : serverTime - receivedAt,
    );
  }

  /// Where the video should be right now.
  double get now {
    if (!playing) return position;
    final serverNow = DateTime.now().millisecondsSinceEpoch + serverOffset;
    return position + math.max(0, serverNow - at) / 1000;
  }
}

/// Writes what the chat watches; the backend stamps the time.
abstract final class WatchStore {
  static String _path(String chat) => '/v1/chats/${chat.toUpperCase()}';

  static Future<void> set(
    String chat, {
    required String videoId,
    required bool playing,
    required double position,
  }) =>
      ApiClient.instance.patch(_path(chat), {
        'watch': {
          'videoId': videoId,
          'playing': playing,
          'position': position,
        },
      });

  /// Ends watching for everyone.
  static Future<void> stop(String chat) =>
      ApiClient.instance.patch(_path(chat), {'watch': <String, dynamic>{}});
}

/// Asks the open chat's notch to show the video, e.g. after "Watch
/// together" under a link.
final watchOpenRequests = ValueNotifier<String?>(null);

/// Starts watching [videoId] in [chat] for everyone and opens the player.
Future<void> watchTogether(String chat, String videoId) async {
  await WatchStore.set(chat, videoId: videoId, playing: true, position: 0);
  watchOpenRequests.value = chat.toUpperCase();
}

/// One player per chat, moved between the notch and full screen rather
/// than built anew there: a new one would load the video from the start.
final _players = <String, (String, GlobalKey<_WatchPlayerState>)>{};

GlobalKey<_WatchPlayerState> _playerKey(String chat, String videoId) {
  final code = chat.toUpperCase();
  final known = _players[code];
  if (known != null && known.$1 == videoId) return known.$2;
  final key = GlobalKey<_WatchPlayerState>();
  _players[code] = (videoId, key);
  return key;
}

/// The notch's YouTube panel: a link to paste, or the shared player.
class WatchPanel extends StatelessWidget {
  const WatchPanel({
    super.key,
    required this.chatCode,
    required this.chat,
    required this.width,
  });

  final String chatCode;
  final Map<String, dynamic>? chat;
  final double width;

  @override
  Widget build(BuildContext context) {
    final state = WatchState.fromChat(chat);
    return Padding(
      padding: const EdgeInsets.fromLTRB(5, 10, 5, 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: state == null
            ? _LinkField(key: const ValueKey('link'), chatCode: chatCode)
            : _WatchPlayer(
                key: _playerKey(chatCode, state.videoId),
                chatCode: chatCode,
                state: state,
                width: width,
              ),
      ),
    );
  }
}

const _clipboard = MethodChannel('sinai/clipboard');

/// The copied link or text. On iOS a copied link may be only a URL, which
/// Flutter's clipboard doesn't read, so the app asks iOS itself.
Future<String?> _clipboardLink() async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      final link = await _clipboard.invokeMethod<String>('link');
      if (link != null) return link;
    } catch (_) {}
  }
  return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

/// Where a YouTube link goes. The clipboard is read only when the user
/// taps paste: reading it unasked makes iOS ask permission every time.
class _LinkField extends StatefulWidget {
  const _LinkField({super.key, required this.chatCode});

  final String chatCode;

  @override
  State<_LinkField> createState() => _LinkFieldState();
}

class _LinkFieldState extends State<_LinkField> {
  bool _busy = false;

  /// Usually the link was just copied in the YouTube app: reads it and
  /// starts it for everyone.
  Future<void> _paste() async {
    final id = youtubeId(await _clipboardLink() ?? '');
    if (!mounted) return;
    if (id == null) {
      showToast('Copy a YouTube link first');
      return;
    }
    setState(() => _busy = true);
    try {
      await WatchStore.set(widget.chatCode,
          videoId: id, playing: true, position: 0);
    } catch (e) {
      debugPrint('Starting the video failed: $e');
      if (mounted) {
        showToast('Could not start the video', kind: ToastKind.error);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 44,
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton.filled(
                    tooltip: 'Paste',
                    onPressed: _paste,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFF0000).withAlpha(32),
                    ),
                    icon: const Icon(AppIcons.copy,
                        size: 20, color: Color(0xFFFF0000)),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap to paste a YouTube link',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The shared player. YouTube's own controls are hidden: play, pause and
/// seeking go through these buttons to everyone, and the player only
/// follows the chat's state, nudged back whenever it drifts.
class _WatchPlayer extends StatefulWidget {
  const _WatchPlayer({
    super.key,
    required this.chatCode,
    required this.state,
    required this.width,
    this.fullscreen = false,
  });

  final String chatCode;
  final WatchState state;
  final double width;

  /// Fills a landscape screen, controls under the video.
  final bool fullscreen;

  @override
  State<_WatchPlayer> createState() => _WatchPlayerState();
}

class _WatchPlayerState extends State<_WatchPlayer> {
  late final YoutubePlayerController _player = YoutubePlayerController(
    params: const YoutubePlayerParams(
      // Taps on the video don't reach YouTube: they would pause it for
      // this phone only, out of step with everyone.
      pointerEvents: PointerEvents.none,
      showControls: false,
      showFullscreenButton: false,
      strictRelatedVideos: true,
      playsInline: true,
    ),
  );

  /// Keeps the video's web view as the player moves between layouts.
  final _view = GlobalKey();

  StreamSubscription<YoutubeVideoState>? _progress;
  Timer? _drift;
  double _seconds = 0;
  double _duration = 0;

  /// The player refused to start on its own (phones need a tap for sound).
  bool _needsTap = false;

  /// Dragging the seek bar: it shows the finger, not the video.
  double? _seeking;

  @override
  void initState() {
    super.initState();
    final s = widget.state;
    if (s.playing) {
      _player.loadVideoById(videoId: s.videoId, startSeconds: s.now);
    } else {
      _player.cueVideoById(videoId: s.videoId, startSeconds: s.now);
    }
    _progress = _player.videoStateStream.listen((v) {
      if (!mounted) return;
      setState(() => _seconds = v.position.inMilliseconds / 1000);
    });
    _drift = Timer.periodic(const Duration(seconds: 2), (_) => _follow());
  }

  @override
  void didUpdateWidget(_WatchPlayer old) {
    super.didUpdateWidget(old);
    if (old.state.at != widget.state.at) _follow();
  }

  /// Brings the player to the chat's state: playing or paused, and at the
  /// right second if it is more than a moment off.
  Future<void> _follow() async {
    final s = widget.state;
    final player = _player.value.playerState;
    if (_duration == 0) {
      final d = await _player.duration;
      if (mounted && d > 0) setState(() => _duration = d);
    }
    final target = s.now;
    final current = await _player.currentTime;
    if ((current - target).abs() > 1.5 && _seeking == null) {
      await _player.seekTo(seconds: target, allowSeekAhead: true);
    }
    if (s.playing && player != PlayerState.playing) {
      await _player.playVideo();
      // Still not playing after asking: the phone wants a tap.
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && widget.state.playing) {
          final stuck = _player.value.playerState != PlayerState.playing &&
              _player.value.playerState != PlayerState.buffering;
          if (stuck != _needsTap) setState(() => _needsTap = stuck);
        }
      });
    } else if (!s.playing && player == PlayerState.playing) {
      await _player.pauseVideo();
    }
    if (s.playing && _player.value.playerState == PlayerState.playing) {
      if (_needsTap) setState(() => _needsTap = false);
    }
  }

  Future<void> _send({required bool playing, required double position}) =>
      WatchStore.set(widget.chatCode,
              videoId: widget.state.videoId,
              playing: playing,
              position: position)
          .catchError((Object e) => debugPrint('Watch update failed: $e'));

  void _togglePlay() {
    final playing = !widget.state.playing;
    // Shown at once; everyone else follows when the chat updates.
    playing ? _player.playVideo() : _player.pauseVideo();
    _send(playing: playing, position: _seconds);
  }

  void _seek(double to) {
    final position = to.clamp(0, _duration > 0 ? _duration : to).toDouble();
    _player.seekTo(seconds: position, allowSeekAhead: true);
    _send(playing: widget.state.playing, position: position);
  }

  @override
  void dispose() {
    _progress?.cancel();
    _drift?.cancel();
    _player.close();
    super.dispose();
  }

  static String _time(double s) {
    final t = s.isFinite ? s.floor() : 0;
    final m = t ~/ 60, sec = (t % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  Widget _controls(Color text) {
    final playing = widget.state.playing;
    final shown = _seeking ?? _seconds;
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: _togglePlay,
          icon: Icon(playing ? AppIcons.pause : AppIcons.play,
              size: 18, color: text),
        ),
        Text(_time(shown), style: TextStyle(fontSize: 12, color: text)),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: _duration > 0 ? shown.clamp(0, _duration) : 0,
              max: _duration > 0 ? _duration : 1,
              activeColor: const Color(0xFFFF0000),
              onChanged:
                  _duration > 0 ? (v) => setState(() => _seeking = v) : null,
              onChangeEnd: (v) {
                setState(() => _seeking = null);
                _seek(v);
              },
            ),
          ),
        ),
        Text(_time(_duration), style: TextStyle(fontSize: 12, color: text)),
        if (widget.fullscreen)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Exit full screen',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(AppIcons.close, size: 18, color: text),
          )
        else
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Stop watching',
            onPressed: () =>
                WatchStore.stop(widget.chatCode).catchError((Object _) {}),
            icon: Icon(AppIcons.close, size: 18, color: text),
          ),
      ],
    );
  }

  Widget _video() => Stack(
        alignment: Alignment.center,
        children: [
          YoutubePlayer(
            key: _view,
            controller: _player,
            aspectRatio: 16 / 9,
            // Full screen is ours (WatchFullscreen), with our controls.
            autoFullScreen: false,
            enableFullScreenOnVerticalDrag: false,
          ),
          if (_needsTap)
            GestureDetector(
              onTap: () {
                _player.playVideo();
                setState(() => _needsTap = false);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(170),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tap to join',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (widget.fullscreen) {
      // Controls under the video, not over it: iOS draws the video's web
      // view above anything laid on top of it.
      return Column(
        children: [
          Expanded(child: Center(child: _video())),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _controls(Colors.white),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: widget.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: _video()),
          _controls(context.colorTheme.textSecondary),
        ],
      ),
    );
  }
}

/// The shared video on the whole screen, turned sideways. It follows the
/// chat's state like the small player, so it carries on where that was.
class WatchFullscreen extends StatefulWidget {
  const WatchFullscreen({
    super.key,
    required this.chatCode,
    required this.initial,
    required this.onHandBack,
  });

  final String chatCode;

  /// The chat as the notch last saw it, so the player moves over at once
  /// instead of waiting for the chat to load.
  final Map<String, dynamic>? initial;

  /// Called the moment the player leaves full screen, in the same frame,
  /// so the notch takes it back without it being rebuilt.
  final VoidCallback onHandBack;

  /// Opens it. The caller must stop showing its own player in the same
  /// frame, and show it again in [onHandBack].
  static Future<void> open(
    BuildContext context,
    String chatCode, {
    required Map<String, dynamic>? chat,
    required VoidCallback onHandBack,
  }) =>
      Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => WatchFullscreen(
          chatCode: chatCode,
          initial: chat,
          onHandBack: onHandBack,
        ),
        // The black screen fades in and the video grows into it.
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween(begin: 0.88, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ));

  @override
  State<WatchFullscreen> createState() => _WatchFullscreenState();
}

class _WatchFullscreenState extends State<WatchFullscreen> {
  late final Stream<Map<String, dynamic>?> _chat = watchChat(widget.chatCode);

  bool _leaving = false;

  /// The player went back to the notch; only black is left here.
  bool _handedBack = false;

  void _handBack() {
    if (_handedBack) return;
    setState(() => _handedBack = true);
    widget.onHandBack();
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Turned sideways once the screen has faded in, not during it, so the
    // two movements don't fight.
    Future.delayed(const Duration(milliseconds: 380), () {
      if (!mounted || _leaving) return;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    });
  }

  /// Turns upright first, then fades back to the chat.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    _handBack();
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (!_handedBack) widget.onHandBack();
    // Back to portrait, as the rest of the app; freeing all orientations
    // here would turn the screen sideways again for a moment.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back gesture or the close button: turn upright, then leave.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: StreamBuilder<Map<String, dynamic>?>(
          stream: _chat,
          initialData: widget.initial,
          builder: (context, snapshot) {
            final state = WatchState.fromChat(snapshot.data);
            if (snapshot.hasData && state == null) {
              // Someone stopped watching: back to the chat.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _leave();
              });
            }
            if (_handedBack) return const SizedBox.expand();
            if (state == null) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            }
            return _WatchPlayer(
              key: _playerKey(widget.chatCode, state.videoId),
              chatCode: widget.chatCode,
              state: state,
              width: MediaQuery.sizeOf(context).width,
              fullscreen: true,
            );
          },
        ),
      ),
    );
  }
}
