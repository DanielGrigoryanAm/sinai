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
class CreateChatScreen extends StatefulWidget {
  const CreateChatScreen({super.key});

  @override
  State<CreateChatScreen> createState() => _CreateChatScreenState();
}

class _CreateChatScreenState extends State<CreateChatScreen> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();

    return BlocProvider(
      create: (_) => ChatBloc(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: const CustomAppBar(showBackButton: true),
          backgroundColor: context.colorTheme.backgroundPrimary,
          body: BlocConsumer<ChatBloc, ChatState>(
            listener: (context, state) {
              if (state is ChatError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(state.message)),
                );
              }
              if (state is ChatCreated) {
                context.router.replace(
                  ChatReadyRoute(chatCode: state.code, chatName: state.name),
                );
              }
            },
            builder: (context, state) {
              final isLoading = state is ChatLoading;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Name your chat',
                      style: context.textTheme.titleLarge.copyWith(
                        fontSize: 30,
                      ),
                    ),
                    const SizedBox(height: 50),
                    CustomTextField(
                      controller: _nameController,
                      hintText: 'Enter chat name',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 20),
                    CustomButton.primary(
                      text: 'Create',
                      isLoading: isLoading,
                      onTap: name.isNotEmpty && !isLoading
                          ? () => context
                              .read<ChatBloc>()
                              .add(CreateChatEvent(name))
                          : null,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
