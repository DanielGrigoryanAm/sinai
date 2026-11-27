import 'package:flutter/material.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/chat/widgets/image_viewer_screen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Someone else's profile, opened from a chat they are in: their photo,
/// name and whether they are online, kept live from the chat.
class PersonProfileScreen extends StatelessWidget {
  const PersonProfileScreen({
    super.key,
    required this.chatCode,
    required this.userId,
    this.name,
    this.photoUrl,
  });

  final String chatCode;
  final String userId;

  /// What the chat already knew, shown until the live copy arrives.
  final String? name;
  final String? photoUrl;

  static Future<void> open(
    BuildContext context, {
    required String chatCode,
    required String userId,
    String? name,
    String? photoUrl,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PersonProfileScreen(
            chatCode: chatCode,
            userId: userId,
            name: name,
            photoUrl: photoUrl,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: const CustomAppBar(showBackButton: true),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: watchChat(chatCode),
        builder: (context, snapshot) {
          final members =
              snapshot.data?['members'] as Map<String, Map<String, dynamic>>?;
          final member = members?[userId];
          final given = ((member?['name'] as String?) ?? name ?? '').trim();
          final shownName = given.isEmpty ? 'No name' : given;
          final photo = (member?['photoUrl'] as String?) ?? photoUrl;
          final online = member?['online'] == true;
          final lastSeen = member?['lastSeen'] as DateTime?;
          final status = online
              ? 'online'
              : lastSeen == null
                  ? null
                  : ChatStatusController.lastSeenText(lastSeen);

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Center(
                child: GestureDetector(
                  // The photo opens full screen, like in a chat.
                  onTap: photo == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ImageViewerScreen(imageUrl: photo),
                            ),
                          ),
                  child: ChatAvatar(
                    title: shownName,
                    photoUrl: photo,
                    size: 128,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                shownName,
                textAlign: TextAlign.center,
                style: text.titleLarge.copyWith(fontSize: 24),
              ),
              if (status != null) ...[
                const SizedBox(height: 4),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: text.bodyLarge.copyWith(
                    fontSize: 15,
                    color: online ? colors.secondary : colors.textSecondary,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
