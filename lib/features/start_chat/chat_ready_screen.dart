import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ChatReadyScreen extends StatefulWidget {
  const ChatReadyScreen({
    super.key,
    required this.chatCode,
    required this.chatName,
  });

  final String chatCode;
  final String chatName;

  @override
  State<ChatReadyScreen> createState() => _ChatReadyScreenState();
}

class _ChatReadyScreenState extends State<ChatReadyScreen> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.chatCode));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  Future<void> _shareCode(BuildContext buttonContext) async {
    // iPad needs an anchor rect for the share popover.
    final box = buttonContext.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Join my chat "${widget.chatName}" in Sinai. '
            'Chat code: ${widget.chatCode}',
        sharePositionOrigin:
            box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      ),
    );
  }

  void _enterChat() {
    context.router.replace(
      ChatRoute(chatCode: widget.chatCode, chatName: widget.chatName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: colors.secondary.withAlpha(40),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: colors.secondary,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          'Your chat is ready',
                          textAlign: TextAlign.center,
                          style: text.titleLarge.copyWith(fontSize: 24),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Share this code to invite others',
                          textAlign: TextAlign.center,
                          style: text.bodyLarge
                              .copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 28,
                          ),
                          decoration: BoxDecoration(
                            color: colors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: colors.border),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14000000),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                'CHAT CODE',
                                style: text.bodySmall.copyWith(
                                  letterSpacing: 0.8,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SelectableText(
                                  widget.chatCode,
                                  style: text.titleLarge.copyWith(
                                    fontSize: 40,
                                    letterSpacing: 4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          spacing: 14,
                          children: [
                            Expanded(
                              child: _OutlineAction(
                                icon:
                                    _copied ? Icons.check : Icons.copy_rounded,
                                label: _copied ? 'Copied' : 'Copy',
                                onTap: _copyCode,
                              ),
                            ),
                            Expanded(
                              child: Builder(
                                builder: (buttonContext) => _OutlineAction(
                                  icon: Icons.share_outlined,
                                  label: 'Share',
                                  onTap: () => _shareCode(buttonContext),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              CustomButton.primary(
                text: 'Enter Chat',
                onTap: _enterChat,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.colorTheme.secondary;

    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              Icon(icon, color: color, size: 20),
              Text(
                label,
                style: context.textTheme.titleSmall.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
