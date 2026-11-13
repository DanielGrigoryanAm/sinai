import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/common/custom_text_field.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatBloc(),
      child: const _ProfileView(),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
  late String _savedName =
      FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
  late final TextEditingController _nameController =
      TextEditingController(text: _savedName);
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save(String name) {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    context.read<ChatBloc>().add(SetUserNameEvent(name));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final name = _nameController.text.trim();
    final canSave = name.isNotEmpty && name != _savedName && !_saving;
    final initialSource = name.isNotEmpty ? name : _savedName;

    return BlocListener<ChatBloc, ChatState>(
      listener: (context, state) {
        if (state is UserNameSaved) {
          setState(() {
            _saving = false;
            _savedName = state.name;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Name saved')),
          );
        }
        if (state is ChatError) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          appBar: const CustomAppBar(title: 'Profile', showBackButton: true),
          backgroundColor: colors.backgroundPrimary,
          body: SafeArea(
            // Scrollable so the form stays reachable above the keyboard.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(30, 24, 30, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECEDF2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        initialSource.isEmpty
                            ? '?'
                            : initialSource.characters.first.toUpperCase(),
                        style: text.titleLarge.copyWith(
                          fontSize: 38,
                          color: const Color(0xFF6B7080),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'YOUR NAME',
                    style: text.bodySmall.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.6,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  CustomTextField(
                    controller: _nameController,
                    hintText: 'Enter your name',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Others see this name next to your new messages. '
                    'Messages you already sent keep the old name.',
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 32),
                  CustomButton.primary(
                    text: 'Save',
                    isLoading: _saving,
                    onTap: canSave ? () => _save(name) : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
