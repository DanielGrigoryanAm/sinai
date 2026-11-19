import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/features/chat/widgets/chat_info_sheet.dart';
import 'package:sinai/features/chat/widgets/message_bubble.dart';
import 'package:sinai/features/chat/widgets/message_field.dart';
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

  void _handleExitToChats() {
    context.router.replaceAll([const ChatsRoute()]);
  }

  Future<void> _openChatInfo() async {
    final leave = await showChatInfoSheet(context, widget.chatCode);
    if (!leave || !mounted) return;
    context.read<ChatBloc>().add(DeleteChatEvent(widget.chatCode));
  }

  @override
  void initState() {
    super.initState();
    _messagesScrollController.addListener(_loadMoreWhenNearTop);
  }

  /// The list is reversed, so the end of the scroll extent is the oldest
  /// loaded message.
  void _loadMoreWhenNearTop() {
    final position = _messagesScrollController.position;
    if (position.pixels < position.maxScrollExtent - 300) return;
    context.read<ChatBloc>().add(const LoadMoreMessagesEvent());
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
    VoicePlayer.instance.stop();
    chatController.dispose();
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
        appBar: CustomAppBar(
          title: widget.chatName ?? 'Chat',
          showBackButton: true,
          onBackPressed: _handleExitToChats,
          actions: [
            IconButton(
              tooltip: 'Chat info',
              icon: const Icon(Icons.more_vert),
              onPressed: _openChatInfo,
            ),
          ],
        ),
        backgroundColor: context.colorTheme.backgroundPrimary,
        body: BlocListener<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state is ChatError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
            if (state is ChatDeleted) {
              _handleExitToChats();
            }
          },
          child: Column(
            children: [
              Expanded(
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
                      final myId = FirebaseAuth.instance.currentUser?.uid;

                      // Reversed, so the newest message stays pinned to the
                      // bottom and older pages load above without moving
                      // what the user is looking at.
                      return ListView.builder(
                        controller: _messagesScrollController,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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

                          return Column(
                            key: ValueKey(message.id),
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (isNewDay) MessageDatePill(date: date),
                              MessageBubble(
                                message: message,
                                isMe: isMe,
                                isSeen: isMe &&
                                    message.createdAt != null &&
                                    state.seenAt != null &&
                                    !state.seenAt!.isBefore(message.createdAt!),
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
                              ),
                            ],
                          );
                        },
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
              BlocBuilder<ChatBloc, ChatState>(
                buildWhen: (previous, current) =>
                    (previous is MessagesLoaded && previous.isSendingImage) !=
                    (current is MessagesLoaded && current.isSendingImage),
                builder: (context, state) {
                  if (state is! MessagesLoaded || !state.isSendingImage) {
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
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: MessageField(
                    chatController: chatController,
                    chatCode: widget.chatCode,
                    onMessageSent: () {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
