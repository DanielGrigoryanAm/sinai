import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/theme/color_theme.dart';

class MessageField extends StatelessWidget {
  const MessageField({
    super.key,
    required this.chatController,
    required this.chatCode,
  });

  final TextEditingController chatController;
  final String chatCode;

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
        decoration: InputDecoration(
            filled: true,
            fillColor: context.colorTheme.backgroundSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide: BorderSide.none,
            ),
            hintText: 'Message...',
            suffixIcon: IconButton(
              icon: Assets.icons.send.image(
                height: 42,
                width: 42,
              ),
              onPressed: () {
                final text = chatController.text.trim();
                if (text.isEmpty) return;
                context.read<ChatBloc>().add(
                      SendMessageEvent(
                        chatCode: chatCode,
                        text: text,
                      ),
                    );

                chatController.clear();
              },
            )),
      ),
    );
  }
}
