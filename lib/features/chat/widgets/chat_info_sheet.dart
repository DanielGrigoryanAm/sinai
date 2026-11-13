import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Bottom sheet with the chat details. Resolves to `true` when the user
/// chose to leave (or, for the owner, delete) the chat.
Future<bool> showChatInfoSheet(BuildContext context, String chatCode) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChatInfoSheet(chatCode: chatCode),
  );
  return result ?? false;
}

class ChatInfoSheet extends StatefulWidget {
  const ChatInfoSheet({super.key, required this.chatCode});

  final String chatCode;

  @override
  State<ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<ChatInfoSheet> {
  static const _dangerColor = Color(0xFFDC2626);

  late final Future<DocumentSnapshot<Map<String, dynamic>>> _chatFuture;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _chatFuture = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatCode)
        .get();
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.chatCode));
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

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            future: _chatFuture,
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              final participants =
                  (data?['participantIds'] as List<dynamic>?)?.length;
              final chatName = (data?['name'] as String?)?.trim() ?? '';
              final isOwner = data != null &&
                  data['ownerId'] == FirebaseAuth.instance.currentUser?.uid;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    chatName.isNotEmpty ? chatName : widget.chatCode,
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    switch (participants) {
                      null => snapshot.hasError ? '' : '…',
                      1 => '1 participant',
                      _ => '$participants participants',
                    },
                    textAlign: TextAlign.center,
                    style: text.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    decoration: BoxDecoration(
                      color: colors.backgroundPrimary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CHAT CODE',
                                style: text.bodySmall.copyWith(
                                  fontSize: 12,
                                  letterSpacing: 0.6,
                                  color: colors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              SelectableText(
                                widget.chatCode,
                                style: text.titleSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy code',
                          onPressed: _copyCode,
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy_rounded,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Divider(height: 1, color: colors.border),
                  const SizedBox(height: 24),
                  Material(
                    color: _dangerColor.withAlpha(18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: _dangerColor.withAlpha(40)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(true),
                      child: SizedBox(
                        height: 56,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 8,
                          children: [
                            Icon(
                              isOwner ? Icons.delete_outline : Icons.logout,
                              color: _dangerColor,
                              size: 20,
                            ),
                            Text(
                              isOwner ? 'Delete chat' : 'Leave chat',
                              style: text.titleSmall
                                  .copyWith(color: _dangerColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Close',
                      style: text.bodyLarge.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
