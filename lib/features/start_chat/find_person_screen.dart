import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_text_field.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Finds someone by their personal code (from their profile) and opens a
/// one-to-one chat with them.
@RoutePage()
class FindPersonScreen extends StatefulWidget {
  const FindPersonScreen({super.key});

  @override
  State<FindPersonScreen> createState() => _FindPersonScreenState();
}

/// Personal codes are this long (chat codes are six).
const _codeLength = 8;

class _FindPersonScreenState extends State<FindPersonScreen> {
  final _controller = TextEditingController();

  /// The code [_person] or [_notFound] is about.
  String _looked = '';
  Person? _person;
  bool _notFound = false;
  bool _searching = false;
  bool _opening = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _code => _controller.text.trim().toUpperCase();

  /// Looks the code up as soon as it is complete.
  void _onChanged(String _) {
    final code = _code;
    setState(() {
      if (code != _looked) {
        _person = null;
        _notFound = false;
      }
    });
    if (code.length == _codeLength && code != _looked) _find(code);
  }

  Future<void> _find(String code) async {
    setState(() {
      _searching = true;
      _looked = code;
    });
    try {
      final person = await ChatsApi.instance.person(code);
      if (!mounted || _code != code) return;
      setState(() => _person = person);
    } on ApiException catch (e) {
      if (!mounted || _code != code) return;
      if (e.isNotFound) {
        setState(() => _notFound = true);
      } else {
        _looked = '';
        showToast(e.message, kind: ToastKind.error);
      }
    } catch (e) {
      debugPrint('Looking up $code failed: $e');
      _looked = '';
      if (mounted) showToast('No connection', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final code = text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (code.isEmpty || !mounted) return;
    _controller.text = code.substring(0, code.length.clamp(0, _codeLength));
    _onChanged(_controller.text);
  }

  Future<void> _message(Person person) async {
    setState(() => _opening = true);
    try {
      final chatCode = await ChatsApi.instance.openDirect(person.code);
      if (!mounted) return;
      // Back from the chat leads to the chats list, not here.
      await context.router.replace(
        ChatRoute(chatCode: chatCode, chatName: person.name),
      );
    } catch (e) {
      debugPrint('Opening the chat with ${person.code} failed: $e');
      if (!mounted) return;
      setState(() => _opening = false);
      showToast(
        e is ApiException ? e.message : 'Could not open the chat',
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final person = _person;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: const CustomAppBar(
          title: 'New message',
          showBackButton: true,
        ),
        backgroundColor: colors.backgroundPrimary,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              Text(
                'Enter their code. They find it in their profile.',
                style: text.bodyLarge.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _controller,
                hintText: 'ENTER THEIR CODE',
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(_codeLength),
                  _UpperCase(),
                ],
                onChanged: _onChanged,
                suffixIcon: TextButton(
                  onPressed: _paste,
                  child: Text(
                    'Paste',
                    style: text.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_searching)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: colors.secondary),
                  ),
                )
              else if (person != null)
                _PersonCard(
                  person: person,
                  isMe: person.id == currentUserId(),
                  busy: _opening,
                  onMessage: () => _message(person),
                )
              else if (_notFound)
                Text(
                  'No one has this code. Check it and try again.',
                  textAlign: TextAlign.center,
                  style: text.bodyLarge.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The person found, drawn like a row of the chats list: photo, name,
/// and a button on the right to write to them.
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.isMe,
    required this.busy,
    required this.onMessage,
  });

  final Person person;
  final bool isMe;
  final bool busy;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final name = person.name.isEmpty ? 'No name' : person.name;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ChatAvatar(title: name, photoUrl: person.photoUrl),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isMe ? 'This is you' : person.code,
                  style: text.bodyLarge.copyWith(
                    fontSize: 15,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: 12),
            Material(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: busy ? null : onMessage,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Message',
                          style: text.bodyLarge.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ],
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
