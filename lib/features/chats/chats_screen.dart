import 'package:auto_route/auto_route.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/notifications/notification_service.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _lastBackPressedAt;
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Asked here rather than at launch, so the permission prompt appears
    // once the user is past onboarding and sees what it is for.
    NotificationService.instance.init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleExitBack() {
    final now = DateTime.now();
    final shouldExit = _lastBackPressedAt != null &&
        now.difference(_lastBackPressedAt!) <= const Duration(seconds: 2);

    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }

    _lastBackPressedAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tap again to exit the app.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  List<ChatSummary> _filter(List<ChatSummary> chats) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return chats;
    return chats
        .where(
          (chat) =>
              chat.title.toLowerCase().contains(query) ||
              chat.code.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return BlocProvider(
      create: (_) => ChatBloc()..add(const GetChatsEvent()),
      child: BlocListener<ChatBloc, ChatState>(
        listener: (context, state) {
          if (state is ChatError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
          if (state is ChatDeleted) {
            context.read<ChatBloc>().add(const GetChatsEvent());
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _handleExitBack();
            }
          },
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              backgroundColor: colors.backgroundPrimary,
              body: SafeArea(
                bottom: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Messages',
                              style: context.textTheme.titleLarge.copyWith(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Material(
                            color: colors.backgroundSecondary,
                            shape: const CircleBorder(),
                            elevation: 2,
                            shadowColor: const Color(0x33000000),
                            clipBehavior: Clip.antiAlias,
                            child: IconButton(
                              tooltip: 'Profile',
                              icon: const Icon(Icons.person_outline),
                              onPressed: () =>
                                  context.router.push(const ProfileRoute()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SearchField(
                        controller: _searchController,
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: BlocBuilder<ChatBloc, ChatState>(
                        builder: _buildBody,
                      ),
                    ),
                  ],
                ),
              ),
              floatingActionButton: SizedBox.square(
                dimension: 64,
                child: FloatingActionButton(
                  onPressed: () => context.router.push(const StartChatRoute()),
                  backgroundColor: colors.secondary,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: const Icon(Icons.add, size: 32),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ChatState state) {
    if (state is ChatLoading || state is ChatInitial) {
      return Center(
        child: CircularProgressIndicator(color: context.colorTheme.secondary),
      );
    }

    if (state is! ChatsLoaded) return const SizedBox.shrink();

    void refresh() => context.read<ChatBloc>().add(const GetChatsEvent());

    if (state.chats.isEmpty) {
      return _EmptyState(
        title: 'No chats yet',
        subtitle: 'Tap + to create or join a chat',
        actionLabel: 'Refresh',
        onAction: refresh,
      );
    }

    final chats = _filter(state.chats);
    if (chats.isEmpty) {
      return const _EmptyState(
        title: 'No chats found',
        subtitle: 'Try a different name or code',
      );
    }

    return RefreshIndicator(
      color: context.colorTheme.secondary,
      onRefresh: () async => refresh(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // Leaves room for the floating button under the last row.
        padding: const EdgeInsets.only(top: 4, bottom: 110),
        itemCount: chats.length,
        itemBuilder: (context, index) {
          final chat = chats[index];
          return Slidable(
            key: ValueKey(chat.code),
            endActionPane: ActionPane(
              motion: const ScrollMotion(),
              extentRatio: 0.2,
              children: [
                SlidableAction(
                  onPressed: (_) async {
                    final bloc = context.read<ChatBloc>();
                    final confirmed = await confirmRemoveChat(
                      context,
                      chatTitle: chat.title,
                      isOwner: chat.isOwner,
                    );
                    if (confirmed) bloc.add(DeleteChatEvent(chat.code));
                  },
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  icon: chat.isOwner ? Icons.delete_outline : Icons.logout,
                ),
              ],
            ),
            child: _ChatRow(
              chat: chat,
              onTap: () => context.router.push(
                ChatRoute(chatCode: chat.code, chatName: chat.name),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return DecoratedBox(
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
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: context.textTheme.bodyLarge,
        cursorColor: colors.secondary,
        decoration: InputDecoration(
          hintText: 'Search chats...',
          hintStyle: context.textTheme.bodyLarge.copyWith(
            color: colors.textSecondary,
          ),
          prefixIcon: Icon(Icons.search, color: colors.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.onTap});

  final ChatSummary chat;
  final VoidCallback onTap;

  String _preview() {
    final message = chat.lastMessage;
    if (message == null) return 'No messages yet';

    final isMine = chat.lastSenderId == FirebaseAuth.instance.currentUser?.uid;
    final sender = isMine ? 'You' : chat.lastSenderName;
    final text = message.replaceAll('\n', ' ');
    return sender == null || sender.isEmpty ? text : '$sender: $text';
  }

  String _time(BuildContext context) {
    final time = chat.lastActivityAt;
    if (time == null) return '';

    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final daysAgo = today.difference(day).inDays;

    if (daysAgo <= 0) {
      return localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(time),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
    }
    if (daysAgo == 1) return 'Yesterday';
    if (time.year == now.year) return localizations.formatShortMonthDay(time);
    return localizations.formatCompactDate(time);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return Material(
      color: colors.backgroundPrimary,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              _ChatAvatar(title: chat.title),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _time(context),
                          style: text.bodySmall.copyWith(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: chat.typingName != null
                              ? Text(
                                  '${chat.typingName} is typing…',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyLarge.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colors.secondary,
                                  ),
                                )
                              : Text(
                                  _preview(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyLarge.copyWith(
                                    fontSize: 15,
                                    fontWeight: chat.hasUnread
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: chat.hasUnread
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                  ),
                                ),
                        ),
                        if (chat.hasUnread) ...[
                          const SizedBox(width: 12),
                          Semantics(
                            label: 'Unread messages',
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circle with the first letter of the chat name.
class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final initial =
        trimmed.isEmpty ? '#' : trimmed.characters.first.toUpperCase();

    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFECEDF2),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        initial,
        style: context.textTheme.titleSmall.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF6B7080),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: text.bodyLarge.copyWith(color: colors.textSecondary),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!,
                  style: text.titleSmall.copyWith(color: colors.secondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
