import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/features/chat/widgets/image_viewer_screen.dart';
import 'package:sinai/features/chat/widgets/message_menu.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/features/chat/widgets/voice_player.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// A single chat message: bubble with the time inside and, for other
/// people's messages, the sender name above the first one of a run.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.startsGroup,
    this.isSeen = false,
    this.myId,
    this.onReact,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.onReplyTap,
  });

  static const _myBubbleColor = Color(0xFF9CC4F0);
  static const _radius = Radius.circular(15);
  static const _tailRadius = Radius.circular(6);

  final ChatMessage message;
  final bool isMe;

  /// First message in a run from the same sender (or of a new day); only
  /// this one gets the sharp top corner.
  final bool startsGroup;

  /// Whether another participant has read this message. Only shown on the
  /// user's own messages.
  final bool isSeen;

  /// Current user's id, to highlight the reaction they left.
  final String? myId;

  /// Called with a reaction id when the user picks or taps a reaction.
  /// Null while the message cannot be reacted to yet.
  final ValueChanged<String>? onReact;

  /// Double tap only ever adds a like, like in most messengers; removing it
  /// is done from the reaction chip or the picker.
  void _like() {
    final mine = message.reactions[myId];
    final like = QuickReactionsStore.instance.like;
    if (mine != null && Reactions.emojiOf(mine) == like) return;
    onReact?.call(like);
  }

  /// Message actions; each is null when it does not apply to this message.
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Tapping the reply quote; scrolls to the message it answers.
  final VoidCallback? onReplyTap;

  /// Long press: reactions plus reply, copy, edit and delete.
  /// Release after dragging through the small reaction strip. Sets the
  /// reaction; picking the one already left keeps it rather than removing.
  void _pickFromScrubber(String emoji) {
    final mine = message.reactions[myId];
    if (mine != null && Reactions.emojiOf(mine) == emoji) return;
    onReact?.call(emoji);
  }

  Future<void> _openMenu(BuildContext bubbleContext) async {
    final canCopy = message.text.trim().isNotEmpty;
    final result = await showMessageMenu(
      bubbleContext,
      currentReaction: message.reactions[myId],
      canReply: onReply != null,
      canCopy: canCopy,
      canEdit: onEdit != null,
      canDelete: onDelete != null,
    );

    switch (result) {
      case MessageMenuReact(:final reaction):
        onReact?.call(reaction);
      case MessageMenuMoreReactions():
        if (!bubbleContext.mounted) return;
        final emoji = await showEmojiPicker(bubbleContext);
        if (emoji != null) onReact?.call(emoji);
      case MessageMenuEditQuick(:final slot):
        if (!bubbleContext.mounted) return;
        await showEmojiPicker(bubbleContext, editSlot: slot);
      case MessageMenuActionResult(action: MessageMenuAction.reply):
        onReply?.call();
      case MessageMenuActionResult(action: MessageMenuAction.copy):
        await Clipboard.setData(ClipboardData(text: message.text));
        if (bubbleContext.mounted) {
          ScaffoldMessenger.of(bubbleContext)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Copied')));
        }
      case MessageMenuActionResult(action: MessageMenuAction.edit):
        onEdit?.call();
      case MessageMenuActionResult(action: MessageMenuAction.delete):
        onDelete?.call();
      case null:
        break;
    }
  }

  String _time(BuildContext context) {
    final time = message.createdAt;
    // The server timestamp is not known yet while the message is being sent.
    if (time == null) return 'Sending…';
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
  }

  static const _shadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Time plus, on the user's own messages, the sent/seen checks.
  Widget _buildMeta(
    BuildContext context, {
    required Color color,
    required Color seenColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        if (message.isEdited)
          Text(
            'edited',
            style: context.textTheme.bodySmall.copyWith(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        Text(
          _time(context),
          style: context.textTheme.bodySmall.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        // One check: sent. Two checks: seen.
        if (isMe && message.createdAt != null)
          Icon(
            isSeen ? Icons.done_all : Icons.check,
            size: 15,
            color: isSeen ? seenColor : color,
            semanticLabel: isSeen ? 'Seen' : 'Sent',
          ),
      ],
    );
  }

  /// Puts the quote of the replied-to message above [content].
  Widget _withQuote(Widget content) {
    final reply = message.replyTo;
    if (reply == null) return content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _ReplyQuote(reply: reply, isMe: isMe, onTap: onReplyTap),
        ),
        content,
      ],
    );
  }

  /// Picture message: the photo fills the bubble and the time sits on a
  /// dark pill over its corner. Tapping opens it full screen.
  Widget _buildImage(BuildContext context, BorderRadius radius) {
    final colors = context.colorTheme;
    final imageUrl = message.imageUrl!;

    final width = message.imageWidth;
    final height = message.imageHeight;
    // Very tall or very wide pictures are cropped in the bubble.
    final aspectRatio = width != null && height != null && height > 0
        ? (width / height).clamp(0.6, 1.8)
        : 1.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerScreen(imageUrl: imageUrl),
        ),
      ),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: radius,
          boxShadow: _shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cached on disk, so a photo is downloaded only once.
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 150),
                placeholder: (context, url) => Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: colors.secondary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: colors.textSecondary,
                    size: 32,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x8C000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildMeta(
                    context,
                    color: Colors.white,
                    seenColor: const Color(0xFF8EC5FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;
    final metaColor = isMe
        ? const Color(0xFF1B2030).withAlpha(140)
        : colors.textSecondary.withAlpha(190);

    final bubbleRadius = BorderRadius.only(
      topLeft: !isMe && startsGroup ? _tailRadius : _radius,
      topRight: isMe && startsGroup ? _tailRadius : _radius,
      bottomLeft: _radius,
      bottomRight: _radius,
    );

    return Padding(
      // Messages of one sender sit close together; a new sender gets air.
      padding: EdgeInsets.only(top: startsGroup ? 12 : 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (startsGroup && !isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: Text(
                    message.senderName,
                    style: text.bodySmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              if (message.replyTo != null &&
                  (message.isImage || message.isVoice))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    decoration: BoxDecoration(
                      color: isMe ? _myBubbleColor : colors.backgroundSecondary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _ReplyQuote(
                      reply: message.replyTo!,
                      isMe: isMe,
                      onTap: onReplyTap,
                    ),
                  ),
                ),
              _DoubleTapLike(
                // Messages still being sent have nothing to act on yet.
                onLongPress: message.createdAt == null ? null : _openMenu,
                onDoubleTap: onReact == null ? null : _like,
                onScrubPick: onReact == null || message.createdAt == null
                    ? null
                    : _pickFromScrubber,
                currentReaction: message.reactions[myId],
                child: message.isImage
                    ? _buildImage(context, bubbleRadius)
                    : message.isVoice
                        ? _VoiceBubble(
                            message: message,
                            color: isMe
                                ? _myBubbleColor
                                : colors.backgroundSecondary,
                            radius: bubbleRadius,
                            accentColor: isMe
                                ? const Color(0xFF1D5FA8)
                                : colors.secondary,
                            meta: _buildMeta(
                              context,
                              color: metaColor,
                              seenColor: const Color(0xFF1D5FA8),
                            ),
                          )
                        : Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? _myBubbleColor
                                  : colors.backgroundSecondary,
                              borderRadius: bubbleRadius,
                              boxShadow: _shadow,
                            ),
                            // The time sits on the last line when it fits next to the
                            // text and drops to its own line otherwise.
                            child: _withQuote(
                              Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.end,
                                spacing: 10,
                                runSpacing: 2,
                                children: [
                                  Text(
                                    message.text,
                                    style: text.bodyLarge.copyWith(
                                      height: 1.4,
                                      color: const Color(0xFF1B2030),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: _buildMeta(
                                      context,
                                      color: metaColor,
                                      seenColor: const Color(0xFF1D5FA8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
              if (message.reactions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
                  child: ReactionChips(
                    reactions: message.reactions,
                    myId: myId,
                    onTap: (reaction) => onReact?.call(reaction),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quote of the message a reply answers: sender and one line of text.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply, required this.isMe, this.onTap});

  final ReplyPreview reply;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent =
        isMe ? const Color(0xFF1D5FA8) : context.colorTheme.secondary;
    final text = context.textTheme;

    final quote = IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reply.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                Text(
                  reply.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall.copyWith(
                    fontSize: 13,
                    color: const Color(0xFF1B2030).withAlpha(170),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return quote;
    return GestureDetector(
      // Opaque so the whole quote, gaps included, takes the tap.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: quote,
    );
  }
}

/// Detects double tap and long press on a bubble and shows a heart that
/// pops over it on double tap.
class _DoubleTapLike extends StatefulWidget {
  const _DoubleTapLike({
    required this.child,
    required this.onDoubleTap,
    required this.onLongPress,
    this.onScrubPick,
    this.currentReaction,
  });

  final Widget child;
  final VoidCallback? onDoubleTap;

  /// Opens the message menu; completes when it closes.
  final Future<void> Function(BuildContext bubbleContext)? onLongPress;

  /// Moving the finger while still holding swaps the menu for a small strip
  /// of reactions, scrolled sideways; this gets the one in its middle on
  /// release.
  final ValueChanged<String>? onScrubPick;

  /// The user's reaction on this message, where the strip starts.
  final String? currentReaction;

  @override
  State<_DoubleTapLike> createState() => _DoubleTapLikeState();
}

class _DoubleTapLikeState extends State<_DoubleTapLike>
    with SingleTickerProviderStateMixin {
  late final AnimationController _heart = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  // Grows past full size, settles, then fades out.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.2, end: 1.2)
          .chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 35,
    ),
    TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
  ]).animate(_heart);

  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 15),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
  ]).animate(_heart);

  /// How far the finger moves before the menu turns into the strip, and
  /// how far it moves per emoji after that.
  static const _scrubThreshold = 14.0;
  static const _scrubStep = 38.0;

  /// Finger x where the strip appeared; sideways travel counts from here.
  double _scrubAnchorX = 0;

  bool _menuOpen = false;
  Offset? _pressStart;
  OverlayEntry? _scrubber;
  final ValueNotifier<double> _scrubPosition = ValueNotifier(0);
  double _scrubStartIndex = 0;
  int _scrubIndex = 0;
  List<String> _scrubEmojis = const [];

  @override
  void dispose() {
    _removeScrubber();
    _scrubPosition.dispose();
    _heart.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _pressStart = details.globalPosition;
    _menuOpen = true;
    widget.onLongPress!(context).whenComplete(() => _menuOpen = false);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    final start = _pressStart;
    if (start == null || widget.onScrubPick == null) return;

    final finger = details.globalPosition;
    if (_scrubber == null) {
      // Any direction starts the strip; after that only sideways counts.
      if ((finger - start).distance < _scrubThreshold) return;
      _scrubAnchorX = finger.dx;
      _startScrubbing(finger);
    }

    // Right moves to the next emoji, left to the previous one. There is
    // room sideways for any message, unlike below the bottom one.
    final travelled = finger.dx - _scrubAnchorX;
    final value = (_scrubStartIndex + travelled / _scrubStep)
        .clamp(0.0, (_scrubEmojis.length - 1).toDouble());
    _scrubPosition.value = value;

    final index = value.round();
    if (index != _scrubIndex) {
      _scrubIndex = index;
      HapticFeedback.selectionClick();
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_scrubber != null) {
      final emoji = _scrubEmojis[_scrubIndex];
      _removeScrubber();
      widget.onScrubPick?.call(emoji);
    }
    _pressStart = null;
  }

  void _startScrubbing(Offset finger) {
    // The finger left the menu: close it and show the strip instead.
    if (_menuOpen) {
      _menuOpen = false;
      closeMessageMenu();
    }

    final current = widget.currentReaction == null
        ? null
        : Reactions.emojiOf(widget.currentReaction!);
    _scrubEmojis = QuickReactionsStore.instance.reactions.value;
    final startIndex = current == null ? -1 : _scrubEmojis.indexOf(current);
    // Without a reaction yet, start in the middle of the set, so either end
    // is at most three steps away.
    _scrubStartIndex = startIndex >= 0
        ? startIndex.toDouble()
        : (_scrubEmojis.length ~/ 2 - 1).toDouble();
    _scrubIndex = _scrubStartIndex.round();
    _scrubPosition.value = _scrubStartIndex;

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final bubbleBox = context.findRenderObject()! as RenderBox;
    final bubble = bubbleBox.localToGlobal(Offset.zero, ancestor: overlayBox) &
        bubbleBox.size;
    final screen = overlayBox.size;
    final topInset = MediaQuery.paddingOf(context).top;

    // Above the bubble when there is room, otherwise below it; centred on
    // the finger and kept on screen.
    const gap = 10.0;
    var top = bubble.top - ReactionScrubber.height - gap;
    if (top < topInset + 8) top = bubble.bottom + gap;
    final left = (finger.dx - ReactionScrubber.width / 2)
        .clamp(12.0, screen.width - ReactionScrubber.width - 12);

    _scrubber = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: ReactionScrubber(
            emojis: _scrubEmojis,
            position: _scrubPosition,
          ),
        ),
      ),
    );
    overlay.insert(_scrubber!);
    HapticFeedback.lightImpact();
  }

  void _removeScrubber() {
    _scrubber?.remove();
    _scrubber = null;
  }

  void _onDoubleTap() {
    HapticFeedback.lightImpact();
    _heart.forward(from: 0);
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: widget.onLongPress == null ? null : _onLongPressStart,
      onLongPressMoveUpdate:
          widget.onLongPress == null ? null : _onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPress == null ? null : _onLongPressEnd,
      onLongPressCancel: () {
        _removeScrubber();
        _pressStart = null;
      },
      onDoubleTap: widget.onDoubleTap == null ? null : _onDoubleTap,
      child: Stack(
        alignment: Alignment.center,
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _heart,
                builder: (context, _) {
                  if (_heart.isDismissed) return const SizedBox.shrink();
                  return Center(
                    child: Opacity(
                      opacity: _opacity.value,
                      child: Transform.scale(
                        scale: _scale.value,
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 44,
                          color: Color(0xFFE5484D),
                          shadows: [
                            Shadow(color: Color(0x40000000), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Voice message: play/pause button, progress and length.
class _VoiceBubble extends StatelessWidget {
  const _VoiceBubble({
    required this.message,
    required this.color,
    required this.radius,
    required this.accentColor,
    required this.meta,
  });

  final ChatMessage message;
  final Color color;
  final BorderRadius radius;
  final Color accentColor;

  /// Time and sent/seen checks, built by the parent bubble.
  final Widget meta;

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await VoicePlayer.instance.toggle(message.audioUrl!);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not play the voice message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = context.textTheme;
    final recorded = Duration(milliseconds: message.audioDurationMs ?? 0);

    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        boxShadow: MessageBubble._shadow,
      ),
      child: ValueListenableBuilder<VoicePlayback>(
        valueListenable: VoicePlayer.instance.playback,
        builder: (context, playback, _) {
          final isCurrent = playback.url == message.audioUrl;
          final isPlaying = isCurrent && playback.isPlaying;

          // The player reports the real length once loaded; until then
          // fall back to the length measured while recording.
          final total = isCurrent && playback.duration > Duration.zero
              ? playback.duration
              : recorded;
          final position = isCurrent ? playback.position : Duration.zero;
          final progress = total.inMilliseconds == 0
              ? 0.0
              : (position.inMilliseconds / total.inMilliseconds)
                  .clamp(0.0, 1.0);

          return Row(
            children: [
              Material(
                color: accentColor,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _toggle(context),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 24,
                      semanticLabel: isPlaying ? 'Pause' : 'Play',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        color: accentColor,
                        backgroundColor: accentColor.withAlpha(50),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          _format(isCurrent ? position : total),
                          style: text.bodySmall.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF1B2030).withAlpha(170),
                          ),
                        ),
                        const Spacer(),
                        meta,
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Centered pill separating messages of different days.
class MessageDatePill extends StatelessWidget {
  const MessageDatePill({super.key, required this.date});

  final DateTime date;

  String _label(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final daysAgo = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;

    if (daysAgo <= 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    if (date.year == now.year) return localizations.formatShortMonthDay(date);
    return localizations.formatShortDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: colors.textSecondary.withAlpha(24),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _label(context),
            style: context.textTheme.bodySmall.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
