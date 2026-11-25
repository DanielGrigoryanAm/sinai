import 'dart:async';
import 'package:sinai/common/app_icons.dart';

import 'package:auto_route/auto_route.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/api/current_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/common/progressive_blur.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/chat/draft_store.dart';
import 'package:sinai/features/chat/forward.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/typing_reporter.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/features/chat/widgets/composer_controller.dart';
import 'package:sinai/features/chat/widgets/chat_header.dart';
import 'package:sinai/features/chat/widgets/chat_info_sheet.dart';
import 'package:sinai/features/chat/widgets/message_bubble.dart';
import 'package:sinai/features/chat/widgets/message_field.dart';
import 'package:sinai/features/chat/widgets/message_menu.dart';
import 'package:sinai/features/chat/widgets/message_search_screen.dart';
import 'package:sinai/features/chat/widgets/voice_player.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.chatCode,
    this.chatName,
  });

  final String chatCode;
  final String? chatName;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc()..add(MessagesSubscribeEvent(chatCode)),
      child: ChatScreenView(
        chatCode: chatCode,
        chatName: chatName,
      ),
    );
  }
}

class ChatScreenView extends StatefulWidget {
  const ChatScreenView({
    super.key,
    required this.chatCode,
    this.chatName,
  });

  final String chatCode;
  final String? chatName;

  @override
  State<ChatScreenView> createState() => _ChatScreenViewState();
}

class _ChatScreenViewState extends State<ChatScreenView> {
  final TextEditingController chatController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final ComposerController _composer = ComposerController();
  final FocusNode _fieldFocus = FocusNode();
  late final ChatStatusController _status =
      ChatStatusController(widget.chatCode);
  late final TypingReporter _typing = TypingReporter(
    chatCode: widget.chatCode,
    controller: chatController,
  );

  /// Height of the input overlay at the bottom, measured after layout.
  double _inputHeight = 90;

  final Map<String, GlobalKey> _messageKeys = {};

  /// Message briefly highlighted after jumping to it from a reply.
  String? _highlightedId;
  Timer? _highlightTimer;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, GlobalKey.new);

  void _showSnack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Scrolls to [messageId], loading older pages if it is not loaded yet,
  /// and highlights it for a moment.
  Future<void> _scrollToMessage(String messageId) async {
    final bloc = context.read<ChatBloc>();

    // 1. Make sure the message is among the loaded ones.
    var state = bloc.state;
    while (state is MessagesLoaded &&
        !state.messages.any((m) => m.id == messageId)) {
      if (!state.hasMore) {
        _showSnack('The original message was deleted');
        return;
      }
      final loadedCount = state.messages.length;
      bloc.add(const LoadMoreMessagesEvent());
      try {
        state = await bloc.stream
            .firstWhere(
              (s) =>
                  s is MessagesLoaded &&
                  !s.isLoadingMore &&
                  s.messages.length > loadedCount,
            )
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        if (mounted) _showSnack('Could not load the original message');
        return;
      }
      if (!mounted) return;
    }
    if (state is! MessagesLoaded) return;
    final messages = state.messages;
    final targetIndex = messages.indexWhere((m) => m.id == messageId);

    // 2. The list builds only what is near the screen, so step towards the
    // message until it has been built, then bring it into view.
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!mounted || !_messagesScrollController.hasClients) return;

      final target = _messageKeys[messageId]?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
        _highlight(messageId);
        return;
      }

      // Any message currently built tells which way to go. The list is
      // reversed: older messages lie at larger scroll offsets.
      int? builtIndex;
      for (var i = 0; i < messages.length; i++) {
        if (_messageKeys[messages[i].id]?.currentContext != null) {
          builtIndex = i;
          break;
        }
      }
      final goOlder = builtIndex == null || targetIndex < builtIndex;

      final position = _messagesScrollController.position;
      final step = position.viewportDimension * 0.9;
      final next = (position.pixels + (goOlder ? step : -step))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) break;
      _messagesScrollController.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }

    if (mounted) _showSnack('Could not find the original message');
  }

  Future<void> _openSearch() async {
    closeMessageMenu();
    final messageId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MessageSearchScreen(chatCode: widget.chatCode),
      ),
    );
    if (messageId != null && mounted) await _scrollToMessage(messageId);
  }

  void _highlight(String messageId) {
    _highlightTimer?.cancel();
    setState(() => _highlightedId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  void _reply(ChatMessage message) {
    _composer.reply(message);
    _fieldFocus.requestFocus();
  }

  void _edit(ChatMessage message) {
    _composer.edit(message);
    chatController.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    _fieldFocus.requestFocus();
  }

  Future<void> _delete(ChatMessage message) async {
    final bloc = context.read<ChatBloc>();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete message?',
      message: 'It will be deleted for everyone in this chat.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;

    // Don't leave a reply or edit pointing at a message that is gone.
    if (_composer.replyTo?.id == message.id) _composer.clear();
    if (_composer.editing?.id == message.id) {
      _composer.clear();
      chatController.clear();
    }

    bloc.add(
      DeleteMessageEvent(chatCode: widget.chatCode, messageId: message.id),
    );
  }

  void _handleExitToChats() {
    context.router.replaceAll([const ChatsRoute()]);
  }

  Future<void> _openChatInfo() async {
    final leave = await showChatInfoSheet(
      context,
      widget.chatCode,
      onSearch: _openSearch,
    );
    if (!leave || !mounted) return;
    context.read<ChatBloc>().add(DeleteChatEvent(widget.chatCode));
  }

  /// Live chat name, so a rename shows up without reopening the chat.
  String? _liveName;
  String? _photoUrl;
  StreamSubscription<Map<String, dynamic>?>? _nameSub;

  @override
  void initState() {
    super.initState();
    final chat = ApiConfig.useBackend
        ? watchChat(widget.chatCode)
        : FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatCode)
            .snapshots()
            .map((doc) => doc.data());
    _nameSub = chat.listen((data) {
      final name = (data?['name'] as String?)?.trim();
      final photoUrl = data?['photoUrl'] as String?;
      if (!mounted) return;
      if ((name != null && name.isNotEmpty && name != _liveName) ||
          photoUrl != _photoUrl) {
        setState(() {
          if (name != null && name.isNotEmpty) _liveName = name;
          _photoUrl = photoUrl;
        });
      }
    }, onError: (_) {});
    _messagesScrollController.addListener(_loadMoreWhenNearTop);
    _messagesScrollController.addListener(_trackScrolledAway);
    chatController.text = DraftStore.instance.get(widget.chatCode);
    chatController.addListener(_saveDraft);
    QuickReactionsStore.instance.start();
    // Created now so typing is reported from the first keystroke.
    _typing;
  }

  /// The list is reversed, so the end of the scroll extent is the oldest
  /// loaded message.
  void _loadMoreWhenNearTop() {
    final position = _messagesScrollController.position;
    if (position.pixels < position.maxScrollExtent - 300) return;
    context.read<ChatBloc>().add(const LoadMoreMessagesEvent());
  }

  void _saveDraft() {
    // Text being edited is the old message, not a draft.
    if (_composer.editing != null) return;
    DraftStore.instance.set(widget.chatCode, chatController.text);
  }

  /// Scrolled up far enough to show the "to the latest" button.
  bool _scrolledAway = false;

  /// Messages from others that arrived while scrolled away.
  int _newWhileAway = 0;
  String? _lastMessageId;

  void _trackScrolledAway() {
    final away = _messagesScrollController.offset > 400;
    if (away == _scrolledAway) return;
    setState(() {
      _scrolledAway = away;
      if (!away) _newWhileAway = 0;
    });
  }

  void _onMessagesChanged(MessagesLoaded state) {
    if (state.messages.isEmpty) return;
    final last = state.messages.last;
    final previous = _lastMessageId;
    _lastMessageId = last.id;
    if (previous == null || previous == last.id || !_scrolledAway) return;
    if (last.senderId == currentUserId()) return;
    setState(() => _newWhileAway++);
  }

  void _scrollToBottom() {
    if (!_messagesScrollController.hasClients) return;

    _messagesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _nameSub?.cancel();
    VoicePlayer.instance.stop();
    // The menu lives in the app-wide overlay; don't leave it behind.
    closeMessageMenu();
    _typing.dispose();
    _status.dispose();
    chatController.dispose();
    _composer.dispose();
    _highlightTimer?.cancel();
    _fieldFocus.dispose();
    _messagesScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleExitToChats();
        }
      },
      child: Scaffold(
        backgroundColor: context.colorTheme.backgroundPrimary,
        body: BlocListener<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state is ChatError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
            if (state is MessagesLoaded) _onMessagesChanged(state);
            if (state is ChatDeleted) {
              _handleExitToChats();
            }
          },
          // The list runs under the input, which sits on a blur that fades
          // in towards the bottom instead of cutting messages off.
          child: Stack(
            children: [
              Positioned.fill(
                // A tap on the messages closes the keyboard, giving the
                // chess board its room back.
                child: GestureDetector(
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, state) {
                      if (state is ChatLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (state is MessagesLoaded) {
                        if (state.messages.isEmpty) {
                          return const Center(child: Text('No messages yet'));
                        }

                        final messages = state.messages;
                        final myId = currentUserId();

                        // Reversed, so the newest message stays pinned to the
                        // bottom and older pages load above without moving
                        // what the user is looking at.
                        return ListView.builder(
                          controller: _messagesScrollController,
                          reverse: true,
                          // Room for the input overlay, so the newest message
                          // can scroll fully above it.
                          // Room for the floating header and input, so the
                          // oldest and newest messages scroll fully clear.
                          padding: EdgeInsets.fromLTRB(
                            16,
                            MediaQuery.paddingOf(context).top +
                                ChatHeader.height +
                                8,
                            16,
                            _inputHeight + 12,
                          ),
                          itemCount:
                              messages.length + (state.isLoadingMore ? 1 : 0),
                          itemBuilder: (context, reversedIndex) {
                            if (reversedIndex == messages.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final index = messages.length - 1 - reversedIndex;
                            final message = messages[index];
                            final isMe = message.senderId == myId;
                            final previous =
                                index > 0 ? messages[index - 1] : null;
                            final date = message.createdAt ?? DateTime.now();
                            final previousDate = previous == null
                                ? null
                                : previous.createdAt ?? DateTime.now();
                            final isNewDay = previousDate == null ||
                                !DateUtils.isSameDay(previousDate, date);

                            return AnimatedContainer(
                              // A GlobalKey lets a reply quote find and scroll
                              // to this message.
                              key: _keyFor(message.id),
                              duration: const Duration(milliseconds: 300),
                              decoration: BoxDecoration(
                                color: _highlightedId == message.id
                                    ? context.colorTheme.secondary.withAlpha(45)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (isNewDay) MessageDatePill(date: date),
                                  MessageBubble(
                                    message: message,
                                    isMe: isMe,
                                    isSeen: isMe &&
                                        message.createdAt != null &&
                                        state.seenAt != null &&
                                        !state.seenAt!
                                            .isBefore(message.createdAt!),
                                    startsGroup: isNewDay ||
                                        previous?.senderId != message.senderId,
                                    myId: myId,
                                    // A message still being sent has no
                                    // server copy to react to yet.
                                    onReact: message.createdAt == null
                                        ? null
                                        : (reaction) =>
                                            context.read<ChatBloc>().add(
                                                  ToggleReactionEvent(
                                                    chatCode: widget.chatCode,
                                                    messageId: message.id,
                                                    reaction: reaction,
                                                  ),
                                                ),
                                    onReply: message.createdAt == null
                                        ? null
                                        : () => _reply(message),
                                    // Only text can be edited; photos and voice
                                    // messages are deleted and sent again.
                                    onForward: message.createdAt == null
                                        ? null
                                        : () =>
                                            forwardMessage(context, message),
                                    onEdit: isMe &&
                                            message.createdAt != null &&
                                            !message.isImage &&
                                            !message.isVoice
                                        ? () => _edit(message)
                                        : null,
                                    onDelete: isMe && message.createdAt != null
                                        ? () => _delete(message)
                                        : null,
                                    onReplyTap: message.replyTo == null
                                        ? null
                                        : () => _scrollToMessage(
                                              message.replyTo!.messageId,
                                            ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: _inputHeight + 8,
                child: AnimatedScale(
                  scale: _scrolledAway ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _ToLatestButton(
                    count: _newWhileAway,
                    onTap: _scrollToBottom,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MeasureSize(
                  onChange: (size) {
                    if (size.height != _inputHeight) {
                      setState(() => _inputHeight = size.height);
                    }
                  },
                  child: Stack(
                    // The blur reaches above the input; the default clip
                    // would cut it off at the input's top as a hard line.
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        top: 15, // the field's top edge, past its padding
                        child: ProgressiveBlur(
                          color: context.colorTheme.backgroundPrimary,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BlocBuilder<ChatBloc, ChatState>(
                            buildWhen: (previous, current) =>
                                (previous is MessagesLoaded &&
                                    previous.isSendingImage) !=
                                (current is MessagesLoaded &&
                                    current.isSendingImage),
                            builder: (context, state) {
                              if (state is! MessagesLoaded ||
                                  !state.isSendingImage) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  spacing: 10,
                                  children: [
                                    SizedBox.square(
                                      dimension: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: context.colorTheme.secondary,
                                      ),
                                    ),
                                    Text(
                                      'Sending…',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.colorTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: MessageField(
                                chatController: chatController,
                                chatCode: widget.chatCode,
                                composer: _composer,
                                focusNode: _fieldFocus,
                                onMessageSent: () {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _scrollToBottom();
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Covers the whole screen so the notch can be touched even
              // when pulled far down; empty parts let touches through.
              Positioned.fill(
                child: ChatHeader(
                  chatCode: widget.chatCode,
                  title: _liveName ?? widget.chatName ?? 'Chat',
                  status: _status.status,
                  onBack: _handleExitToChats,
                  onInfo: _openChatInfo,
                  onSearch: _openSearch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round button that jumps to the newest message, with the number of new
/// messages that arrived while the user was reading older ones.
class _ToLatestButton extends StatelessWidget {
  const _ToLatestButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                AppIcons.arrowDown,
                size: 20,
                color: colors.textPrimary,
                semanticLabel: 'Latest messages',
              ),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            top: -6,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                constraints: const BoxConstraints(minWidth: 20),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
