import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/common/photo_crop_screen.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/auth/account_link.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/account/account_options.dart';
import 'package:sinai/common/toast.dart';
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

  bool _signingOut = false;

  /// Asks what to do with the photo: pick one, or remove the current one.
  Future<void> _onPhotoTap() async {
    if (_photoUrl == null) return _pickPhoto();
    final colors = context.colorTheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: colors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(AppIcons.addImage, color: colors.secondary),
                title: const Text('Choose a new photo'),
                onTap: () => Navigator.pop(context, 'pick'),
              ),
              ListTile(
                leading: const Icon(AppIcons.trash, color: Color(0xFFDC2626)),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 'pick') await _pickPhoto();
    if (choice == 'remove') await _removePhoto();
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await pickRoundPhoto(context);
      if (photo == null || !mounted) return;
      setState(() => _uploadingPhoto = true);
      final me = await AuthApi.instance.setPhoto(photo.bytes, photo.type);
      if (mounted) setState(() => _photoUrl = me.photoUrl);
    } catch (e) {
      debugPrint('Changing the profile photo failed: $e');
      showToast('Could not change the photo', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      await AuthApi.instance.removePhoto();
      if (mounted) setState(() => _photoUrl = null);
    } catch (e) {
      debugPrint('Removing the profile photo failed: $e');
      showToast('Could not remove the photo', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign out?',
      message: 'Your chats stay with your account. Sign in with the same '
          'Google account to get them back, or with another one.',
      confirmLabel: 'Sign out',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _signingOut = true);
    await signOut(context);
  }

  /// The user's own code, once the backend has sent it.
  String? _code;

  @override
  void initState() {
    super.initState();
    _loadCode();
  }

  /// The profile photo; null shows the first letter.
  String? _photoUrl;
  bool _uploadingPhoto = false;

  Future<void> _loadCode() async {
    try {
      final me = await AuthApi.instance.me();
      if (!mounted) return;
      setState(() {
        if (me.code.isNotEmpty) _code = me.code;
        _photoUrl = me.photoUrl;
      });
    } catch (e) {
      debugPrint('Could not load the profile: $e');
    }
  }

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
          showToast('Name saved', kind: ToastKind.success);
        }
        if (state is ChatError) {
          setState(() => _saving = false);
          showToast(state.message, kind: ToastKind.error);
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
                    child: _ProfilePhoto(
                      title: initialSource.isEmpty ? '?' : initialSource,
                      photoUrl: _photoUrl,
                      busy: _uploadingPhoto,
                      onTap: _uploadingPhoto ? null : _onPhotoTap,
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    'YOUR CODE',
                    style: text.bodySmall.copyWith(
                      fontSize: 12,
                      letterSpacing: 0.6,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _CodeCard(code: _code),
                  const SizedBox(height: 10),
                  Text(
                    'Others write to you by this code. Share it with '
                    'people you want to talk to.',
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 32),
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
                  if (AccountSection.enabled) ...[
                    const SizedBox(height: 40),
                    Text(
                      'ACCOUNT',
                      style: text.bodySmall.copyWith(
                        fontSize: 12,
                        letterSpacing: 0.6,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AccountSection(),
                  ],
                  const SizedBox(height: 24),
                  CustomButton.outline(
                    text: 'Sign out',
                    leadingIcon: AppIcons.logout,
                    color: const Color(0xFFDC2626),
                    isLoading: _signingOut,
                    onTap: _signingOut ? null : _signOut,
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

/// The user's code in large letters, copied on tap.
class _CodeCard extends StatefulWidget {
  const _CodeCard({required this.code});

  /// Null while it loads.
  final String? code;

  @override
  State<_CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<_CodeCard> {
  bool _copied = false;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final code = widget.code;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: code == null ? null : () => _copy(code),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code ?? '········',
                  style: text.titleLarge.copyWith(
                    fontSize: 22,
                    letterSpacing: 3,
                    color: code == null ? colors.textSecondary : null,
                  ),
                ),
              ),
              Icon(
                _copied ? AppIcons.check : AppIcons.copy,
                size: 20,
                color: colors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The profile photo (or first letter) with a camera badge; a tap changes
/// it.
class _ProfilePhoto extends StatelessWidget {
  const _ProfilePhoto({
    required this.title,
    required this.photoUrl,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String? photoUrl;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ChatAvatar(title: title, photoUrl: photoUrl, size: 96),
          if (busy)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x66000000),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.backgroundPrimary,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  AppIcons.camera,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
