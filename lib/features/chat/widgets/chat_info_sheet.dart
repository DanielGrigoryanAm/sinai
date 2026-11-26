import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:sinai/features/chat/widgets/mini_games_screen.dart';
import 'package:sinai/features/settings/app_colors_screen.dart';
import 'package:sinai/features/chat/widgets/chat_media_screen.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/chat_watch.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/common/photo_compress.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/features/presence/presence_service.dart';
import 'package:sinai/features/presence/realtime_db.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/common/app_icons.dart';

/// Bottom sheet with the chat details. Resolves to `true` when the user
/// chose to leave (or, for the owner, delete) the chat.
Future<bool> showChatInfoSheet(
  BuildContext context,
  String chatCode, {
  VoidCallback? onSearch,
}) async {
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        ChatInfoSheet(chatCode: chatCode, canSearch: onSearch != null),
  );
  if (result == _searchResult) onSearch?.call();
  return result == true;
}

const _searchResult = 'search';

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Material(
      color: colors.backgroundPrimary,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: colors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: context.textTheme.bodyLarge.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Icon(AppIcons.arrowRight, size: 18, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatInfoSheet extends StatefulWidget {
  const ChatInfoSheet({
    super.key,
    required this.chatCode,
    this.canSearch = false,
  });

  final String chatCode;

  /// Shows a "Search messages" row; picking it closes the sheet.
  final bool canSearch;

  @override
  State<ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<ChatInfoSheet> {
  static const _dangerColor = Color(0xFFDC2626);

  // Live, so a new photo or a removed member shows at once.
  late final Stream<Map<String, dynamic>?> _chat = ApiConfig.useBackend
      ? watchChat(widget.chatCode)
      : FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatCode)
          .snapshots()
          .map((doc) => doc.data());
  bool _copied = false;
  bool _uploadingPhoto = false;

  String? get _me => currentUserId();

  /// Owner only: picks a photo and makes it the chat's picture.
  Future<void> _changePhoto(String? oldPhotoUrl) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _uploadingPhoto = true);

      if (ApiConfig.useBackend) {
        final photo = await compressPhoto(
          await picked.readAsBytes(),
          picked.mimeType ?? 'image/jpeg',
          maxSide: 600,
        );
        await ChatsApi.instance.setPhoto(
          widget.chatCode,
          photo.bytes,
          photo.type,
        );
        return;
      }

      final ref = FirebaseStorage.instance.ref(
        'chats/${widget.chatCode}/avatar/'
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putData(
        await picked.readAsBytes(),
        SettableMetadata(contentType: picked.mimeType ?? 'image/jpeg'),
      );
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatCode)
          .update({'photoUrl': url});

      // The previous photo is no longer used.
      if (oldPhotoUrl != null && oldPhotoUrl.isNotEmpty) {
        FirebaseStorage.instance
            .refFromURL(oldPhotoUrl)
            .delete()
            .catchError((Object _) {});
      }
    } catch (e) {
      debugPrint('Changing the chat photo failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not change the photo')),
      );
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// Owner only: takes a member out of the chat.
  Future<void> _removeMember(String uid, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove $name?',
      message: 'They will lose access to this chat. They can join again '
          'with its code.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      if (ApiConfig.useBackend) {
        await ChatsApi.instance.removeMember(widget.chatCode, uid);
        return;
      }
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatCode)
          .update({
        'participantIds': FieldValue.arrayRemove([uid]),
      });
    } catch (e) {
      debugPrint('Removing a member failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not remove the member')),
      );
    }
  }

  /// Owner only: renames the chat for everyone.
  Future<void> _rename(String current) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chat name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == current) return;
    try {
      if (ApiConfig.useBackend) {
        await ChatsApi.instance.rename(widget.chatCode, trimmed);
        return;
      }
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatCode)
          .update({'name': trimmed});
    } catch (e) {
      debugPrint('Renaming the chat failed: $e');
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not rename the chat')),
      );
    }
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
          child: StreamBuilder<Map<String, dynamic>?>(
            stream: _chat,
            builder: (context, snapshot) {
              final data = snapshot.data;
              // Names and online status, when the backend sends them.
              final memberInfo =
                  data?['members'] as Map<String, Map<String, dynamic>>?;
              final memberIds = ((data?['participantIds'] as List?) ?? [])
                  .whereType<String>()
                  .toList();
              final chatName = (data?['name'] as String?)?.trim() ?? '';
              final ownerId = data?['ownerId'] as String?;
              final isOwner = data != null && ownerId == _me;
              final photoUrl = data?['photoUrl'] as String?;
              // Owner first, then the user, then everyone else.
              memberIds.sort((a, b) {
                int rank(String uid) =>
                    uid == ownerId ? 0 : (uid == _me ? 1 : 2);
                return rank(a).compareTo(rank(b));
              });

              return SingleChildScrollView(
                child: Column(
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
                    const SizedBox(height: 20),
                    Center(
                      child: GestureDetector(
                        onTap: isOwner && !_uploadingPhoto
                            ? () => _changePhoto(photoUrl)
                            : null,
                        child: Stack(
                          children: [
                            ChatAvatar(
                              title: chatName.isNotEmpty
                                  ? chatName
                                  : widget.chatCode,
                              photoUrl: photoUrl,
                              size: 84,
                            ),
                            if (_uploadingPhoto)
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
                              ),
                            // Only the owner can change the photo.
                            if (isOwner && !_uploadingPhoto)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: colors.secondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.backgroundSecondary,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    AppIcons.camera,
                                    size: 16,
                                    color: Colors.white,
                                    semanticLabel: 'Change chat photo',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: isOwner ? () => _rename(chatName) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              chatName.isNotEmpty ? chatName : widget.chatCode,
                              textAlign: TextAlign.center,
                              style: text.titleLarge,
                            ),
                          ),
                          if (isOwner) ...[
                            const SizedBox(width: 6),
                            Icon(
                              AppIcons.edit,
                              size: 18,
                              color: colors.textSecondary,
                              semanticLabel: 'Rename chat',
                            ),
                          ],
                        ],
                      ),
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
                              _copied ? AppIcons.check : AppIcons.copy,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SheetRow(
                      icon: AppIcons.game,
                      label: 'Mini games',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              MiniGamesScreen(chatCode: widget.chatCode),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SheetRow(
                      icon: AppIcons.palette,
                      label: 'App colors',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AppColorsScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: colors.backgroundPrimary,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChatMediaScreen(chatCode: widget.chatCode),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Icon(AppIcons.images, color: colors.textPrimary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Photos & voice messages',
                                  style: text.bodyLarge.copyWith(
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(
                                AppIcons.arrowRight,
                                size: 18,
                                color: colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (memberIds.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'MEMBERS · ${memberIds.length}',
                        style: text.bodySmall.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.6,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final uid in memberIds)
                        _MemberRow(
                          chatCode: widget.chatCode,
                          uid: uid,
                          isMe: uid == _me,
                          isOwner: uid == ownerId,
                          info: memberInfo?[uid],
                          onRemove: isOwner && uid != _me
                              ? (name) => _removeMember(uid, name)
                              : null,
                        ),
                    ],
                    const SizedBox(height: 16),
                    Material(
                      color: _dangerColor.withAlpha(18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: _dangerColor.withAlpha(40)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          final confirmed = await confirmRemoveChat(
                            context,
                            chatTitle: chatName.isNotEmpty
                                ? chatName
                                : widget.chatCode,
                            isOwner: isOwner,
                          );
                          if (confirmed && context.mounted) {
                            Navigator.of(context).pop(true);
                          }
                        },
                        child: SizedBox(
                          height: 56,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: 8,
                            children: [
                              Icon(
                                isOwner ? AppIcons.trash : AppIcons.logout,
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
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One member: avatar, name, owner mark, online dot and, for the owner,
/// a remove button. The name comes from the member's presence.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.uid,
    required this.chatCode,
    required this.isMe,
    required this.isOwner,
    required this.onRemove,
    this.info,
  });

  /// Name and online status from the backend; null reads them from
  /// Firebase instead.
  final Map<String, dynamic>? info;

  final String uid;
  final String chatCode;

  /// Cached so sheet rebuilds don't refetch or flash "Member".
  static final _senderNames = <String, Future<String?>>{};
  final bool isMe;
  final bool isOwner;

  /// Called with the member's name; null when they cannot be removed.
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final known = info;
    if (known != null) {
      final given = (known['name'] as String?) ?? '';
      final name = given.isNotEmpty ? given : (isMe ? 'You' : 'Member');
      return _content(
        context,
        name,
        known['online'] == true,
        known['lastSeen'] as DateTime?,
      );
    }

    // Members on older app versions don't publish their name in presence;
    // fall back to the name on one of their messages in this chat.
    final senderName = _senderNames.putIfAbsent(
        '$chatCode/$uid',
        () => FirebaseFirestore.instance
            .collection('chats')
            .doc(chatCode)
            .collection('messages')
            .where('senderId', isEqualTo: uid)
            .limit(1)
            .get()
            .then((q) => q.docs.isEmpty
                ? null
                : (q.docs.first.data()['senderName'] as String?)?.trim())
            .catchError((_) => null));

    return FutureBuilder<String?>(
      future: senderName,
      builder: (context, nameSnap) => StreamBuilder<DatabaseEvent>(
        stream: RealtimeDb.presence(uid).onValue,
        builder: (context, snapshot) {
          final presence = Presence.fromValue(snapshot.data?.snapshot.value);
          final myName = FirebaseAuth.instance.currentUser?.displayName;
          final name = isMe
              ? (myName?.trim().isNotEmpty ?? false ? myName!.trim() : 'You')
              : (presence.name?.trim().isNotEmpty ?? false
                  ? presence.name!.trim()
                  : (nameSnap.data?.isNotEmpty ?? false
                      ? nameSnap.data!
                      : 'Member'));
          return _content(context, name, presence.online, presence.lastSeen);
        },
      ),
    );
  }

  Widget _content(
    BuildContext context,
    String name,
    bool online,
    DateTime? lastSeen,
  ) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final status = online
        ? 'online'
        : lastSeen == null
            ? null
            : ChatStatusController.lastSeenText(lastSeen);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Stack(
            children: [
              ChatAvatar(title: name, size: 40),
              if (online && !isMe)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.backgroundSecondary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (you)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (status != null && !isMe)
                  Text(
                    status,
                    style: text.bodySmall.copyWith(
                      fontSize: 12,
                      color: online ? colors.secondary : colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (isOwner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.secondary.withAlpha(40),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'owner',
                style: text.bodySmall.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.secondary,
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove $name',
              icon: Icon(
                AppIcons.userMinus,
                size: 20,
                color: colors.textSecondary,
              ),
              onPressed: () => onRemove!(name),
            ),
        ],
      ),
    );
  }
}
