import 'package:flutter/material.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/api/chats_api.dart';

/// Asks which chat to forward [message] to and sends a copy there.
Future<void> forwardMessage(
  BuildContext context,
  ChatMessage message, {
  required String fromChat,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final target = await showModalBottomSheet<_ChatOption>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colorTheme.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _ForwardSheet(),
  );
  if (target == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('Forwarding to ${target.title}…')));
  try {
    // The server copies the message, its photo or voice file included.
    await ChatsApi.instance.forward(
      fromChat: fromChat,
      messageId: message.id,
      toChat: target.code,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Forwarded to ${target.title}')));
  } catch (e) {
    debugPrint('Forwarding failed: $e');
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Could not forward')));
  }
}

class _ChatOption {
  const _ChatOption(this.code, this.title, this.photoUrl);

  final String code;
  final String title;
  final String? photoUrl;
}

class _ForwardSheet extends StatelessWidget {
  const _ForwardSheet();

  /// The user's chats to forward to, by name.
  static Future<List<_ChatOption>> _chats() async {
    final chats = [
      for (final chat in await ChatsApi.instance.chats())
        _ChatOption(chat.code, chat.title, chat.photoUrl),
    ];
    return chats..sort((a, b) => a.title.compareTo(b.title));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('Forward to', style: context.textTheme.titleLarge),
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<List<_ChatOption>>(
                future: _chats(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final chats = snapshot.data!;

                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: chats.length,
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return ListTile(
                        leading: ChatAvatar(
                          title: chat.title,
                          photoUrl: chat.photoUrl,
                          size: 44,
                        ),
                        title: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodyLarge.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(chat),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
