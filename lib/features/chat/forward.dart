import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Asks which chat to forward [message] to and sends a copy there.
Future<void> forwardMessage(BuildContext context, ChatMessage message) async {
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
    await _send(message, target.code);
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

/// Writes a copy of [message] into [chatCode]. Photos and voice messages are
/// copied into the target chat's storage, so the copy survives the original
/// being deleted.
Future<void> _send(ChatMessage message, String chatCode) async {
  final user = FirebaseAuth.instance.currentUser!;
  final stamp = '${DateTime.now().millisecondsSinceEpoch}_${user.uid}';

  Future<String> copyFile(String url, String path, String type) async {
    final bytes = await FirebaseStorage.instance
        .refFromURL(url)
        .getData(25 * 1024 * 1024);
    if (bytes == null) throw StateError('Empty file');
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: type));
    return ref.getDownloadURL();
  }

  final senderName =
      user.displayName?.isNotEmpty == true ? user.displayName! : 'Guest';

  await FirebaseFirestore.instance
      .collection('chats')
      .doc(chatCode)
      .collection('messages')
      .add({
    'text': message.text,
    if (message.isImage) ...{
      'imageUrl': await copyFile(
        message.imageUrl!,
        'chats/$chatCode/images/$stamp.jpg',
        'image/jpeg',
      ),
      'imageWidth': message.imageWidth,
      'imageHeight': message.imageHeight,
    },
    if (message.isVoice) ...{
      'audioUrl': await copyFile(
        message.audioUrl!,
        'chats/$chatCode/audio/$stamp.m4a',
        'audio/mp4',
      ),
      'audioDurationMs': message.audioDurationMs,
    },
    // Forwarding a forward keeps the original author.
    'forwardedFrom': message.forwardedFrom ?? message.senderName,
    'senderId': user.uid,
    'senderName': senderName,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

class _ChatOption {
  const _ChatOption(this.code, this.title, this.photoUrl);

  final String code;
  final String title;
  final String? photoUrl;
}

class _ForwardSheet extends StatelessWidget {
  const _ForwardSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
              child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance
                    .collection('chats')
                    .where('participantIds', arrayContains: uid)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final chats = snapshot.data!.docs.map((doc) {
                    final name = (doc.data()['name'] as String?)?.trim();
                    return _ChatOption(
                      doc.id,
                      name == null || name.isEmpty ? doc.id : name,
                      doc.data()['photoUrl'] as String?,
                    );
                  }).toList()
                    ..sort((a, b) => a.title.compareTo(b.title));

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
