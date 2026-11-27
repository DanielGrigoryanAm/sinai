import 'package:auto_route/auto_route.dart';
import 'package:sinai/api/current_user.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/features/chat/draft_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sinai/common/chat_avatar.dart';
import 'package:sinai/common/confirm_dialog.dart';
import 'package:sinai/common/round_field.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';
import 'package:sinai/features/chats/widgets/new_chat_menu.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/notifications/notification_service.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/common/app_icons.dart';

@RoutePage()
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  DateTime? _lastBackPressedAt;
  String _query = '';

  /// The + menu: 0 shut, 1 open.
  late final AnimationController _menu = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );

  bool get _menuOpen =>
      _menu.status == AnimationStatus.forward ||
      _menu.status == AnimationStatus.completed;

  void _toggleMenu() => _menuOpen ? _menu.reverse() : _menu.forward();

  /// Shuts the menu and opens [route].
  void _openFromMenu(PageRouteInfo route) {
    _menu.reverse();
    context.router.push(route);
  }

  /// The list's bloc; reloaded whenever this screen is on top again.
  final ChatBloc _bloc = ChatBloc()..add(const GetChatsEvent());
  StackRouter? _router;
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    // Asked here rather than at launch, so the permission prompt appears
    // once the user is past onboarding and sees what it is for.
    NotificationService.instance.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = context.router;
    if (router != _router) {
      _router?.removeListener(_onRoutesChanged);
      _router = router..addListener(_onRoutesChanged);
    }
  }

  /// Back on this screen from a chat, a new chat or a new message: the
  /// list may have a chat it doesn't show yet, so it reloads quietly.
  void _onRoutesChanged() {
    final onTop = _router?.current.name == ChatsRoute.name;
    if (onTop && !_onTop) _bloc.add(const GetChatsEvent());
    _onTop = onTop;
  }

  @override
  void dispose() {
    _router?.removeListener(_onRoutesChanged);
    _bloc.close();
    _menu.dispose();
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
    showToast('Tap again to exit the app.',
        duration: const Duration(seconds: 2));
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

    return BlocProvider.value(
      value: _bloc,
      child: BlocListener<ChatBloc, ChatState>(
        listener: (context, state) {
          if (state is ChatError) {
            showToast(state.message, kind: ToastKind.error);
          }
          if (state is ChatDeleted) {
            context.read<ChatBloc>().add(const GetChatsEvent());
          }
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_menuOpen) {
              _menu.reverse();
            } else {
              _handleExitBack();
            }
          },
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              backgroundColor: colors.backgroundPrimary,
              body: Stack(
                children: [
                  SafeArea(
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
                                  icon: const ProfileIcon(),
                                  onPressed: () =>
                                      context.router.push(const ProfileRoute()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          // The same field as message search.
                          child: RoundField(
                            controller: _searchController,
                            hintText: 'Search chats...',
                            onChanged: (value) =>
                                setState(() => _query = value),
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
                  // Dims the list while the + menu is open; a tap shuts it.
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _menu,
                      builder: (context, _) => IgnorePointer(
                        ignoring: _menu.value == 0,
                        child: GestureDetector(
                          onTap: _menu.reverse,
                          child: ColoredBox(
                            color: colors.backgroundPrimary.withValues(
                                alpha: 0.85 * _menu.value.clamp(0.0, 1.0)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              floatingActionButton: NewChatMenu(
                animation: _menu,
                onToggle: _toggleMenu,
                actions: [
                  NewChatAction(
                    label: 'New chat',
                    icon: AppIcons.chat,
                    onTap: () => _openFromMenu(const StartChatRoute()),
                  ),
                  NewChatAction(
                    label: 'New message',
                    icon: AppIcons.user,
                    onTap: () => _openFromMenu(const FindPersonRoute()),
                  ),
                ],
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
        subtitle: 'Tap + to start a new chat or message',
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
                  icon: chat.isOwner ? AppIcons.trash : AppIcons.logout,
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

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.chat, required this.onTap});

  final ChatSummary chat;
  final VoidCallback onTap;

  String _preview() {
    final message = chat.lastMessage;
    if (message == null) return 'No messages yet';

    final isMine = chat.lastSenderId == currentUserId();
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
              ChatAvatar(title: chat.title, photoUrl: chat.photoUrl),
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
                              : ValueListenableBuilder<Map<String, String>>(
                                  valueListenable: DraftStore.instance.drafts,
                                  builder: (context, drafts, preview) {
                                    final draft = drafts[chat.code]?.trim();
                                    if (draft == null || draft.isEmpty) {
                                      return preview!;
                                    }
                                    return Text.rich(
                                      TextSpan(children: [
                                        const TextSpan(
                                          text: 'Draft: ',
                                          style: TextStyle(
                                            color: Color(0xFFDC2626),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        TextSpan(
                                          text: draft.replaceAll('\n', ' '),
                                        ),
                                      ]),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodyLarge.copyWith(
                                        fontSize: 15,
                                        color: colors.textSecondary,
                                      ),
                                    );
                                  },
                                  child: Text(
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
                                  )),
                        ),
                        if (chat.hasUnread) ...[
                          const SizedBox(width: 12),
                          _UnreadBadge(count: chat.unreadCount),
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

/// Number of unread messages in a gold pill; a dot while still counting.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final count = this.count;

    if (count == null || count == 0) {
      return Semantics(
        label: 'Unread messages',
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colors.secondary,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    return Semantics(
      label: '$count unread messages',
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.secondary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
