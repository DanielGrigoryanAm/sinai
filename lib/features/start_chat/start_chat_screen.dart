import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/settings_section.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';

import 'bloc/chat_bloc.dart';

/// New chat: join one by its code, or make one. Drawn like the profile:
/// sections of white rows, the action in the row.
@RoutePage()
class StartChatScreen extends StatefulWidget {
  const StartChatScreen({super.key});

  @override
  State<StartChatScreen> createState() => _StartChatScreenState();
}

/// Chat codes are this long.
const _codeLength = 6;

class _StartChatScreenState extends State<StartChatScreen> {
  final TextEditingController _chatCodeController = TextEditingController();

  @override
  void dispose() {
    _chatCodeController.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final code = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (code.isEmpty || !mounted) return;
    setState(() => _chatCodeController.text =
        code.substring(0, code.length.clamp(0, _codeLength)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final code = _chatCodeController.text.trim();

    return BlocProvider(
      create: (_) => ChatBloc(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: const CustomAppBar(title: 'New chat', showBackButton: true),
          backgroundColor: colors.backgroundPrimary,
          body: BlocConsumer<ChatBloc, ChatState>(
            listener: (context, state) {
              if (state is ChatError) {
                showToast(state.message, kind: ToastKind.error);
              }
              if (state is ChatJoined) {
                // Back from the chat leads to the chats list, not here.
                context.router.replace(ChatRoute(chatCode: state.code));
              }
            },
            builder: (context, state) {
              final joining = state is ChatLoading;
              void join() => context.read<ChatBloc>().add(JoinChatEvent(code));
              final canJoin = code.length == _codeLength && !joining;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  SettingsSection(
                    label: 'Join a chat',
                    caption: 'Ask someone in the chat for its 6-character '
                        'code.',
                    rows: [
                      SettingsRow(
                        trailing: code.isEmpty
                            ? SettingsRowAction(label: 'Paste', onTap: _paste)
                            : SettingsRowAction(
                                label: 'Join',
                                busy: joining,
                                onTap: canJoin ? join : null,
                              ),
                        child: SettingsField(
                          controller: _chatCodeController,
                          hintText: 'Chat code',
                          letterSpacing: 2,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp('[A-Za-z0-9]')),
                            LengthLimitingTextInputFormatter(_codeLength),
                            _UpperCase(),
                          ],
                          onChanged: (_) => setState(() {}),
                          onSubmitted: (_) {
                            if (canJoin) join();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SettingsSection(
                    label: 'Or make your own',
                    caption: 'You get a code to share with the people you '
                        'want in it.',
                    rows: [
                      SettingsRow(
                        leading: PlusIcon(
                          size: 20,
                          strokeWidth: 1.8,
                          color: colors.secondary,
                        ),
                        trailing: Icon(
                          AppIcons.arrowRight,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        onTap: () =>
                            context.router.push(const CreateChatRoute()),
                        child: const Text('Create a chat'),
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

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
