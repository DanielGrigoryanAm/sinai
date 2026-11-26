import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/chat/widgets/chat_games.dart';
import 'package:sinai/features/chat/widgets/notch_extras.dart';
import 'package:sinai/features/chat/widgets/notch_menu.dart';
import 'package:sinai/features/chat/widgets/watch_together.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/api/chat_watch.dart';

/// Chat header: the back and menu buttons are tabs growing out of the
/// screen edges, with the chat name and status between them. Messages
/// scroll underneath and fade out behind it.
class ChatHeader extends StatefulWidget implements PreferredSizeWidget {
  const ChatHeader({
    super.key,
    required this.chatCode,
    required this.title,
    required this.status,
    required this.onBack,
    required this.onInfo,
    required this.onSearch,
  });

  static const height = 88.0;

  final String chatCode;
  final String title;
  final ValueListenable<ChatStatus?> status;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onSearch;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader> {
  /// The chat document, which holds the game.
  Map<String, dynamic>? _chat;

  StreamSubscription<Map<String, dynamic>?>? _gameSub;

  @override
  void initState() {
    super.initState();
    final chat = watchChat(widget.chatCode);
    _gameSub = chat.listen((data) {
      if (mounted) setState(() => _chat = data);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _gameSub?.cancel();
    super.dispose();
  }

  String get title => widget.title;
  ValueListenable<ChatStatus?> get status => widget.status;
  VoidCallback get onBack => widget.onBack;
  VoidCallback get onInfo => widget.onInfo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _build);

  Widget _build(BuildContext context, BoxConstraints constraints) {
    final colors = context.colorTheme;
    final top = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;

    // The board takes the notch's full width but leaves the lower half of
    // the screen to the messages. The header spans the space above the
    // keyboard, so the board shrinks while it's open.
    final chessSize = math
        .min(
          // The notch's side margin inside its walls.
          width - 2 * (_NotchShape.fillet + _notchInset),
          // Everything else in the notch: name, status and grabber.
          constraints.maxHeight / 2 - top - 105,
        )
        .clamp(120.0, double.infinity);

    return Stack(
      // The fade reaches below the header; clipping would cut it as a line.
      clipBehavior: Clip.none,
      children: [
        // Fades the messages scrolling under the header.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top + ChatHeader.height + 24,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.backgroundPrimary.withAlpha(190),
                    colors.backgroundPrimary.withAlpha(120),
                    colors.backgroundPrimary.withAlpha(0),
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        // The name and status hang from the top edge like a notch.
        // Not held to the header's height, so it can be pulled down.
        OverflowBox(
          alignment: Alignment.topCenter,
          maxHeight: double.infinity,
          child: _Notch(
            narrowWidth: width - 2 * (_EdgeTab._width + 6),
            wide: ChatGames.shown(_chat).isWide,
            top: 0,
            onTap: onInfo,
            board: (_) => ChatGames(
              chatCode: widget.chatCode,
              chat: _chat,
              chessSize: chessSize,
            ),
            watchPanel: (width) => WatchPanel(
              chatCode: widget.chatCode,
              chat: _chat,
              width: width,
            ),
            watchWidth: chessSize,
            chat: _chat,
            watching: WatchState.fromChat(_chat) != null,
            chatCode: widget.chatCode,
            onStartGame: (type) =>
                ChatGames.startType(widget.chatCode, type).catchError((_) {}),
            status: status,
            waiting: ChatGames.waitsOnMe(_chat),
            playing: ChatGames.playing(_chat) != null,
            onRestart: () =>
                ChatGames.restart(widget.chatCode, _chat).catchError((_) {}),
            onCancel: () =>
                ChatGames.cancel(widget.chatCode, _chat).catchError((_) {}),
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, top + 6, 18, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleLarge.copyWith(
                      fontSize: 18,
                      height: 1.2,
                    ),
                  ),
                  ValueListenableBuilder<ChatStatus?>(
                    valueListenable: status,
                    builder: (context, status, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        status?.text ?? '',
                        key: ValueKey(status?.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          fontWeight: status?.active ?? false
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: status?.active ?? false
                              ? colors.secondary
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Above the notch, which spreads under them to fit the chess board.
        Padding(
          // Raised so the tabs' bottom lines up with the notch's: the notch is
          // 6 + 38.5 (title and status) + 10 + 11 (grabber) tall below the status bar, a tab
          // is curve + body tall.
          padding: EdgeInsets.only(
            top: (top + 54.5 + 11 - _EdgeTab._tabHeight - _EdgeTab._fillet)
                .clamp(0, double.infinity),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EdgeTab(
                side: _Side.left,
                icon: AppIcons.arrowLeft,
                tooltip: 'Back',
                onTap: onBack,
              ),
              const Spacer(),
              // The left tab's curve is above it and this one's below, so
              // this one moves down by the curve to line up with it.
              Padding(
                padding: const EdgeInsets.only(top: _EdgeTab._fillet),
                child: _EdgeTab(
                  side: _Side.right,
                  icon: AppIcons.search,
                  tooltip: 'Search',
                  onTap: widget.onSearch,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _Side { left, right }

/// White container hanging from the top edge, flowing into it with
/// concave curves on both sides, like a laptop's camera notch.
/// Side margin inside the notch's walls, for all it shows.
const _notchInset = 6.0;

class _Notch extends StatefulWidget {
  const _Notch({
    required this.child,
    required this.onTap,
    required this.top,
    required this.narrowWidth,
    required this.wide,
    required this.board,
    required this.onStartGame,
    required this.watchPanel,
    required this.watchWidth,
    required this.chat,
    required this.watching,
    required this.chatCode,
    required this.status,
    required this.waiting,
    required this.playing,
    required this.onRestart,
    required this.onCancel,
  });

  /// For the typing dots shown in the droplet.
  final ValueListenable<ChatStatus?> status;

  /// A game is being played: pulling further offers to restart or cancel it.
  final bool playing;
  final VoidCallback onRestart;
  final VoidCallback onCancel;

  /// Width the notch keeps to between the side tabs.
  final double narrowWidth;

  /// The board needs the full width: the notch spreads out while showing it.
  final bool wide;

  /// Shown under the name while the notch is pulled far down; armed once
  /// it's pulled far enough that letting go starts a game.
  final Widget Function(bool armed) board;

  /// A game was picked in the pulled-down menu.
  final ValueChanged<ChatGameType> onStartGame;

  /// The YouTube panel: a link to paste, or the shared player.
  final Widget Function(double width) watchPanel;
  final double watchWidth;

  /// The chat as last loaded, handed to full screen.
  final Map<String, dynamic>? chat;

  /// The chat is watching a video together.
  final bool watching;

  /// To answer requests to open the player for this chat.
  final String chatCode;

  /// A game waits on this user: the notch hops to say so.
  final bool waiting;

  /// Where the curves start; 0 hangs it from the very top.
  final double top;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Notch> createState() => _NotchState();
}

/// Starts as a small droplet hanging from the top. Pulling it down grows
/// it into the full notch with the chat name; pushing it up shrinks it back.
/// Pulled past full size it stretches like rubber and wobbles back; pulled
/// far enough, it opens the game board. Pushing up closes the board.
class _NotchState extends State<_Notch> with TickerProviderStateMixin {
  static const _grabber = 4.0;
  static const _grabberGap = 7.0;

  /// Droplet size below the status bar.
  static const _dropWidth = 56.0;
  static const _dropHeight = 22.0;

  /// How far to drag to go from droplet to notch.
  static const _openDistance = 110.0;

  /// Whether the notch was left open, remembered between chats and launches.
  static const _prefKey = 'chat_notch_open';
  static bool? _savedOpen;

  /// 0 is the droplet, 1 the full notch.
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: _savedOpen ?? false ? 1 : 0,
  )..addListener(() => setState(() {}));

  @override
  void initState() {
    super.initState();
    watchOpenRequests.addListener(_onWatchRequest);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncHop();
    });
    if (_savedOpen == null) {
      SharedPreferences.getInstance().then((prefs) {
        _savedOpen = prefs.getBool(_prefKey) ?? false;
        if (mounted && _savedOpen! && !_open.isAnimating) {
          _open.value = 1;
        }
      });
    }
  }

  /// Animates to the droplet or the notch and remembers which.
  void _settle(bool open) {
    _open.animateTo(open ? 1 : 0, curve: Curves.easeOutBack);
    if (_savedOpen == open) return;
    _savedOpen = open;
    SharedPreferences.getInstance().then((p) => p.setBool(_prefKey, open));
  }

  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addListener(() => setState(() => _pull = _snapFrom * (1 - _curve())));

  /// How far past full size to pull to open the board.
  static const _boardPull = 120.0;

  /// Pulled this far, the board starts showing.
  static const _boardPeek = 30.0;

  bool _showBoard = false;

  /// The icon menu (games, YouTube), when no game is being played.
  bool _showMenu = false;

  /// The YouTube panel.
  bool _showWatch = false;

  /// Restart and cancel buttons under a game being played.
  bool _showActions = false;

  /// Vertical travel of the current drag.
  double _gestureDy = 0;

  /// Hops the notch down every 10 seconds while a game or a video waits
  /// on the user; each hop takes 300 ms.
  static const _hopEvery = Duration(seconds: 10);
  static const _hopUp = 300 / 10000;

  late final AnimationController _hop = AnimationController(
    vsync: this,
    duration: _hopEvery,
  )..addListener(() {
      // Rebuilds only during the hop, not for the rest of the wait.
      if (_hop.value < _hopUp * 1.2) setState(() {});
    });

  double get _hopOffset {
    final t = _hop.value;
    return t < _hopUp ? 16 * math.sin(math.pi * t / _hopUp) : 0;
  }

  void _syncHop() {
    // A game waiting on the user, or a video the chat watches without them.
    final hop =
        (widget.waiting && !_showBoard) || (widget.watching && !_showWatch);
    if (hop && !_hop.isAnimating) {
      _hop.repeat();
    } else if (!hop && _hop.isAnimating) {
      _hop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(_Notch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.playing) _showActions = false;
    _syncHop();
  }

  /// Finger travel: the first [_openDistance] opens, the rest stretches.
  double _drag = 0;
  double _pull = 0;
  double _snapFrom = 0;

  double _curve() => Curves.elasticOut.transform(_snap.value);

  void _start(DragStartDetails _) {
    _gestureDy = 0;
    _open.stop();
    _snap.stop();
    _drag = _open.value * _openDistance + _stretchToDrag(_pull);
  }

  double get _limit => MediaQuery.sizeOf(context).height / 2;

  // Follows the finger at first and gets harder to pull further down,
  // reaching about half the screen.
  double _dragToStretch(double d) => _limit * (1 - math.exp(-1.5 * d / _limit));
  double _stretchToDrag(double s) =>
      s <= 0 ? 0 : -_limit / 1.5 * math.log(1 - (s / _limit).clamp(0, 0.99));

  /// How far past full size to pull the open video into full screen.
  static const _fullscreenPull = 170.0;

  /// The pull already went full screen; the rest of the gesture is ignored.
  bool _gestureSpent = false;

  /// How full the "pull for full screen" bar is.
  double get _fullscreenProgress =>
      ((_pull - _boardPeek) / (_fullscreenPull - _boardPeek)).clamp(0.0, 1.0);

  bool get _pullingToFullscreen => _showWatch && widget.watching;

  void _update(DragUpdateDetails details) {
    if (_gestureSpent) return;
    _drag = math.max(0, _drag + details.delta.dy);
    _gestureDy += details.delta.dy;
    if ((_showBoard || _showMenu || _showWatch) && _gestureDy < -30) {
      _showBoard = false;
      _showMenu = false;
      _showWatch = false;
      _showActions = false;
      _syncHop();
    }
    setState(() {
      _open.value = (_drag / _openDistance).clamp(0, 1);
      _pull = _dragToStretch(math.max(0, _drag - _openDistance));
    });
    // Filled the bar: full screen right away, no need to let go.
    if (_pullingToFullscreen && _pull >= _fullscreenPull) {
      _gestureSpent = true;
      HapticFeedback.mediumImpact();
      _drag = 0;
      _snapFrom = _pull;
      _snap.forward(from: 0);
      _openFullscreen();
    }
  }

  void _release([DragEndDetails? details]) {
    if (_gestureSpent) {
      _gestureSpent = false;
      return;
    }
    _drag = 0;
    if (_pull > _boardPull) {
      if (widget.watching && !_showWatch) {
        // The video the chat is watching comes first.
        _showWatch = true;
        _showMenu = false;
        _showBoard = false;
      } else if (widget.watching && _showWatch) {
        // Let go before the bar filled: nothing, it just springs back.
      } else if (widget.playing) {
        // Already playing: the further pull brings up the game's buttons.
        if (_showBoard) _showActions = true;
        _showBoard = true;
        // The menu may still be open from before the game started; the
        // board takes its place.
        _showMenu = false;
      } else {
        // Otherwise the menu: games, YouTube.
        _showMenu = true;
        _showBoard = false;
      }
      _syncHop();
    }
    if (_pull > 0) {
      _snapFrom = _pull;
      _snap.forward(from: 0);
      _settle(true);
      return;
    }
    final velocity = details?.primaryVelocity ?? 0;
    final open = velocity.abs() > 300 ? velocity > 0 : _open.value > 0.5;
    _settle(open);
  }

  void _tap() {
    if (_open.value < 1) {
      _settle(true);
    } else {
      widget.onTap();
    }
  }

  void _openWatch() {
    setState(() {
      _showWatch = true;
      _showMenu = false;
      _showBoard = false;
    });
    _settle(true);
    _syncHop();
  }

  /// The video on the whole screen, sideways. The small player closes
  /// meanwhile, so the sound doesn't play twice, and comes back after.
  Future<void> _openFullscreen() async {
    // The player moves to full screen in the same frame the notch lets go.
    setState(() => _showWatch = false);
    await WatchFullscreen.open(
      context,
      widget.chatCode,
      chat: widget.chat,
      onHandBack: () {
        if (mounted) setState(() => _showWatch = widget.watching);
      },
    );
    if (!mounted) return;
    _syncHop();
  }

  /// "Watch together" under a link opens this chat's player.
  void _onWatchRequest() {
    if (watchOpenRequests.value == widget.chatCode.toUpperCase()) {
      watchOpenRequests.value = null;
      _openWatch();
    }
  }

  /// Starts the picked game and shows its board in place of the menu.
  void _startGame(ChatGameType type) {
    setState(() {
      _showMenu = false;
      _showBoard = true;
    });
    _syncHop();
    widget.onStartGame(type);
  }

  void _restart() {
    setState(() => _showActions = false);
    widget.onRestart();
  }

  /// Ends the game and folds the board away, leaving the notch open.
  void _cancel() {
    setState(() {
      _showActions = false;
      _showBoard = false;
    });
    _settle(true);
    _syncHop();
    widget.onCancel();
  }

  Widget _actions() {
    final colors = context.colorTheme;
    Widget button(String label, IconData icon, VoidCallback onTap) =>
        TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 16),
          label: Text(label),
          style: TextButton.styleFrom(
            backgroundColor: colors.secondary.withAlpha(40),
            foregroundColor: colors.textPrimary,
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          button('Restart', AppIcons.refresh, _restart),
          button('Cancel', AppIcons.close, _cancel),
        ],
      ),
    );
  }

  @override
  void dispose() {
    watchOpenRequests.removeListener(_onWatchRequest);
    _hop.dispose();
    _open.dispose();
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shape = _NotchShape(widget.top);
    final open = _open.value;
    final top = MediaQuery.paddingOf(context).top;
    // While a game is on, pulling peeks at its board; otherwise at the
    // menu, unless a game was just picked.
    final peeking = _pull > _boardPeek;
    final watchShown = _showWatch;
    final boardShown = !watchShown &&
        ((widget.playing && peeking) || (_showBoard && !_showMenu));
    final menuShown = !watchShown &&
        !boardShown &&
        (_showMenu || (peeking && !widget.playing));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (boardShown && widget.wide) || watchShown
            ? double.infinity
            : widget.narrowWidth,
      ),
      child: GestureDetector(
        onVerticalDragStart: _start,
        onVerticalDragUpdate: _update,
        onVerticalDragEnd: _release,
        onVerticalDragCancel: _release,
        child: CustomPaint(
          painter: _ShadowPainter(shape),
          child: ClipPath(
            clipper: shape,
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: _tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _NotchShape.fillet,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: _dropWidth,
                      minHeight: top + _dropHeight,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // The name and status grow out of the droplet.
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            widthFactor: open.clamp(0, 1.2),
                            heightFactor: open.clamp(0, 1.2),
                            child: Opacity(
                              opacity: (open * open).clamp(0, 1),
                              // Grows and shrinks smoothly as the status
                              // text changes.
                              child: AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                // The one side margin for everything in the
                                // notch; what goes inside adds none.
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: _notchInset,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      widget.child,
                                      if (menuShown)
                                        // Taps on the icons stay in the menu.
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {},
                                          child: NotchMenu(
                                            onGame: _startGame,
                                            onYoutube: _openWatch,
                                          ),
                                        ),
                                      if (watchShown)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {},
                                          child: widget.watchPanel(
                                            widget.watchWidth,
                                          ),
                                        ),
                                      if (boardShown)
                                        // Taps on the game stay in the game instead of
                                        // opening the chat info.
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          // Also closes the keyboard, letting
                                          // the board grow back.
                                          onTap: () => FocusManager
                                              .instance.primaryFocus
                                              ?.unfocus(),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              widget.board(_pull > _boardPull),
                                              // Shown while pulling a game in
                                              // play further, and kept after.
                                              if (widget.playing &&
                                                  (_showActions ||
                                                      (_showBoard &&
                                                          _pull > _boardPeek)))
                                                _actions(),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        NotchExtras(status: widget.status, folded: open < 0.5),
                        // Overshoots up a little while wobbling back; never
                        // shrinks below its own size.
                        SizedBox(
                          height: _pull.clamp(0, double.infinity) + _hopOffset,
                          // With the video open, the pull says what it does.
                          child: _pullingToFullscreen && _pull > _boardPeek
                              ? _FullscreenHint(progress: _fullscreenProgress)
                              : null,
                        ),
                        // A home-indicator bar hinting that it can be pulled.
                        Container(
                          width: 36,
                          height: _grabber,
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(45),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: _grabberGap),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotchShape extends CustomClipper<Path> {
  const _NotchShape(this.top);

  final double top;

  static const fillet = 16.0;
  static const _radius = 22.0;

  @override
  Path getClip(Size size) {
    const f = fillet;
    const r = _radius;
    final w = size.width;
    final h = size.height;
    final t = top;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(0, t)
      ..quadraticBezierTo(f, t, f, t + f)
      ..lineTo(f, h - r)
      ..quadraticBezierTo(f, h, f + r, h)
      ..lineTo(w - f - r, h)
      ..quadraticBezierTo(w - f, h, w - f, h - r)
      ..lineTo(w - f, t + f)
      ..quadraticBezierTo(w - f, t, w, t)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(_NotchShape oldClipper) => oldClipper.top != top;
}

/// A button shaped as a tab attached to the screen edge. A concave curve
/// flows it into the edge: above the left tab, below the right one.
class _EdgeTab extends StatelessWidget {
  const _EdgeTab({
    required this.side,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  static const _width = 53.0;
  static const _tabHeight = 45.0;
  static const _fillet = 16.0;

  final _Side side;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = _EdgeTabShape(side);
    final isLeft = side == _Side.left;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _width,
        height: _tabHeight + _fillet,
        child: CustomPaint(
          painter: _ShadowPainter(shape),
          child: ClipPath(
            clipper: shape,
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  // The icon sits in the tab, not in the curve.
                  padding: EdgeInsets.only(
                    top: isLeft ? _fillet : 0,
                    bottom: isLeft ? 0 : _fillet,
                    left: isLeft ? 0 : 6,
                    right: isLeft ? 6 : 0,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 20,
                      color: context.colorTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeTabShape extends CustomClipper<Path> {
  const _EdgeTabShape(this.side);

  final _Side side;

  static const _radius = 18.0;

  @override
  Path getClip(Size size) {
    const f = _EdgeTab._fillet;
    const r = _radius;
    final w = size.width;
    final h = size.height;

    // Drawn for the left side, with the curve on top; the right tab is
    // the same shape turned half a turn.
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(0, f, f, f)
      ..lineTo(w - r, f)
      ..quadraticBezierTo(w, f, w, f + r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(0, h)
      ..close();

    if (side == _Side.left) return path;
    return path.transform(
      (Matrix4.identity()
            ..translateByDouble(w, h, 0, 1)
            ..rotateZ(3.141592653589793))
          .storage,
    );
  }

  @override
  bool shouldReclip(_EdgeTabShape oldClipper) => oldClipper.side != side;
}

class _ShadowPainter extends CustomPainter {
  const _ShadowPainter(this.shape);

  final CustomClipper<Path> shape;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(
      shape.getClip(size),
      const Color(0x55000000),
      5,
      false,
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) => oldDelegate.shape != shape;
}

/// "Pull down for full screen" with a bar that fills as the notch is
/// pulled; full screen opens the moment it is full.
class _FullscreenHint extends StatelessWidget {
  const _FullscreenHint({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final full = progress >= 1;
    return Center(
      child: Opacity(
        opacity: (progress * 3).clamp(0.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              full ? 'Opening full screen…' : 'Pull down for full screen',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: full ? const Color(0xFFFF0000) : colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  color: const Color(0xFFFF0000),
                  backgroundColor: colors.border,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
