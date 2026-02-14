import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/common/custom_text_field.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

import 'bloc/chat_bloc.dart';

@RoutePage()
class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});

  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final TextEditingController _chatCodeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(),
      child: Scaffold(
        appBar: CustomAppBar(
          showBackButton: true,
        ),
        backgroundColor: context.colorTheme.backgroundPrimary,
        body: BlocConsumer<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state is ChatError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
            if (state is ChatCreated) {
              context.router.push(ChatRoute(chatCode: state.code));
            }
            if (state is ChatJoined) {
              context.router.push(ChatRoute(chatCode: state.code));
            }
          },
          builder: (context, state) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Start Chatting',
                  style: context.textTheme.titleLarge.copyWith(
                    fontSize: 30,
                  ),
                ),
                SizedBox(height: 50),
                CustomTextField(
                  controller: _chatCodeController,
                  hintText: 'ENTER CHAT CODE',
                ),
                SizedBox(height: 20),
                CustomButton.primary(
                  text: 'Join',
                  trailingIcon: Icons.arrow_forward,
                  onTap: () {
                    context.read<ChatBloc>().add(
                          JoinChatEvent(_chatCodeController.text),
                        );
                  },
                ),
                SizedBox(height: 30),
                Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: Text(
                        'OR',
                        style: context.textTheme.hintText,
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: 30),
                CustomButton.outline(
                  text: 'Create chat',
                  leadingIcon: Icons.add,
                  isLoading: state is ChatLoading,
                  onTap: () {
                    context.read<ChatBloc>().add(const CreateChatEvent());
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
