import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

class MessageField extends StatelessWidget {
  const MessageField({
    super.key,
    required this.chatController,
    required this.chatCode,
    this.onMessageSent,
  });

  final TextEditingController chatController;
  final String chatCode;
  final VoidCallback? onMessageSent;

  void _send(BuildContext context) {
    final text = chatController.text.trim();
    if (text.isEmpty) return;
    context.read<ChatBloc>().add(
          SendMessageEvent(
            chatCode: chatCode,
            text: text,
          ),
        );

    chatController.clear();
    onMessageSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        cursorColor: context.colorTheme.secondary,
        controller: chatController,
        textInputAction: TextInputAction.send,
        textCapitalization: TextCapitalization.sentences,
        // Handling the action here instead of onSubmitted keeps the keyboard
        // open, so several messages can be sent in a row.
        onEditingComplete: () => _send(context),
        decoration: InputDecoration(
            filled: true,
            fillColor: context.colorTheme.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide: BorderSide.none,
            ),
            hintText: 'Message...',
            hintStyle: context.textTheme.hintText.copyWith(
              fontSize: 16,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: IconButton(
                icon: Assets.icons.send.image(
                  height: 35,
                  width: 35,
                ),
                onPressed: () => _send(context),
              ),
            )),
      ),
    );
  }
}
