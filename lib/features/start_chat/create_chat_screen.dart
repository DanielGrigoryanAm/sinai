import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/settings_section.dart';
import 'package:sinai/router/app_router.dart';
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
          appBar:
              const CustomAppBar(title: 'Create a chat', showBackButton: true),
          backgroundColor: context.colorTheme.backgroundPrimary,
          body: BlocConsumer<ChatBloc, ChatState>(
            listener: (context, state) {
              if (state is ChatError) {
                showToast(state.message, kind: ToastKind.error);
              }
              if (state is ChatCreated) {
                context.router.replace(
                  ChatReadyRoute(chatCode: state.code, chatName: state.name),
                );
              }
            },
            builder: (context, state) {
              final isLoading = state is ChatLoading;
              final canCreate = name.isNotEmpty && !isLoading;
              void create() =>
                  context.read<ChatBloc>().add(CreateChatEvent(name));

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  SettingsSection(
                    label: 'Chat name',
                    caption: 'Everyone in the chat sees it. You can change '
                        'it later.',
                    rows: [
                      SettingsRow(
                        trailing: SettingsRowAction(
                          label: 'Create',
                          busy: isLoading,
                          onTap: canCreate ? create : null,
                        ),
                        child: SettingsField(
                          controller: _nameController,
                          hintText: 'Enter chat name',
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (canCreate) create();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
