import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/features/chat/widgets/message_field.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.chatCode,
  });

  final String chatCode;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc()..add(MessagesSubscribeEvent(chatCode)),
      child: ChatScreenView(
        chatCode: chatCode,
      ),
    );
  }
}

class ChatScreenView extends StatefulWidget {
  const ChatScreenView({
    super.key,
    required this.chatCode,
  });

  final String chatCode;

  @override
  State<ChatScreenView> createState() => _ChatScreenViewState();
}

class _ChatScreenViewState extends State<ChatScreenView> {
  final TextEditingController chatController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  int _lastMessagesCount = 0;

  void _handleExitToChats() {
    context.router.replaceAll([const ChatsRoute()]);
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_messagesScrollController.hasClients) return;

    final targetOffset = _messagesScrollController.position.maxScrollExtent;
    if (animated) {
      _messagesScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    _messagesScrollController.jumpTo(targetOffset);
  }

  @override
  void dispose() {
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
          title: widget.chatCode,
          showBackButton: true,
          onBackPressed: _handleExitToChats,
        ),
        backgroundColor: context.colorTheme.backgroundPrimary,
        body: BlocListener<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state is ChatError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
            if (state is MessagesLoaded && state.messages.isNotEmpty) {
              final hasNewMessages = state.messages.length != _lastMessagesCount;
              _lastMessagesCount = state.messages.length;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom(animated: hasNewMessages);
              });
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

                      return ListView.builder(
                        controller: _messagesScrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final message = state.messages[index];
                          final myId = FirebaseAuth.instance.currentUser?.uid;
                          final isMe = message.senderId == myId;
                          final showName = index == 0 ||
                              index > 0 &&
                                  state.messages[index - 1].senderId !=
                                      message.senderId;

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (showName)
                                  Text(
                                    message.senderName,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  spacing: 6,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      message.createdAt != null
                                          ? '${message.createdAt!.hour.toString().padLeft(2, '0')}:${message.createdAt!.minute.toString().padLeft(2, '0')}'
                                          : '...',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Flexible(
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? Colors.blue.shade200
                                              : Colors.grey.shade200,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          message.text,
                                          // softWrap: true,
                                        ),
                                      ),
                                    ),
                                  ],
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
