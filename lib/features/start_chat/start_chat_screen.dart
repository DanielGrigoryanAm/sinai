import 'dart:developer';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

import 'bloc/chat_bloc.dart';

@RoutePage()
class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});

  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

class _StartChatScreenState extends State<StartChatScreen> {
  final TextEditingController chatCodeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(),
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Start Chatting',
        ),
        backgroundColor: context.colorTheme.backgroundSecondary,
        body: BlocConsumer<ChatBloc, ChatState>(
          listener: (context, state) {
            if (state is ChatError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }

            if (state is ChatCreated) {
              log('>>>>Chat created with code: ${state.code}');
              context.router.push(ChatRoute(chatCode: state.code));
            }

            if (state is ChatJoined) {
              log('>>>>Joined chat with code: ${state.code}');
              context.router.push(ChatRoute(chatCode: state.code));
            }
          },
          builder: (context, state) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: chatCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                    hintText: 'Enter chat code',
                  ),
                ),
                SizedBox(height: 10),
                CustomButton(
                  text: 'Join',
                  onTap: () {
                    context.read<ChatBloc>().add(
                          JoinChatEvent(chatCodeController.text),
                        );
                  },
                ),
                SizedBox(height: 20),
                Text('--- or ---'),
                SizedBox(height: 20),
                CustomButton(
                  text: 'Create chat',
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
