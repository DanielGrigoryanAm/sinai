import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/common/app_icons.dart';
import 'dart:async';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/common/round_field.dart';

/// Searches a chat's messages by text. Pops with the id of the tapped
/// message, so the chat can scroll to it.
///
/// The server searches the whole chat, however long.
class MessageSearchScreen extends StatefulWidget {
  const MessageSearchScreen({super.key, required this.chatCode});

  final String chatCode;

  @override
  State<MessageSearchScreen> createState() => _MessageSearchScreenState();
}

class _SearchItem {
  const _SearchItem({
    required this.id,
    required this.text,
    required this.senderName,
    required this.createdAt,
  });

  final String id;
  final String text;
  final String senderName;
  final DateTime? createdAt;
}

class _MessageSearchScreenState extends State<MessageSearchScreen> {
  final TextEditingController _query = TextEditingController();
  Future<List<_SearchItem>> _messages = Future.value(const []);

  /// The search runs on the server, a moment after the user stops typing.
  Timer? _searchSoon;
  String _searched = '';

  void _onQueryChanged() {
    final query = _query.text.trim();
    _searchSoon?.cancel();
    if (query.length < 2 || query == _searched) return;
    _searchSoon = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _searched = query;
        _messages = ChatsApi.instance.search(widget.chatCode, query).then(
              (list) => [
                for (final m in list)
                  if (m.text.trim().isNotEmpty)
                    _SearchItem(
                      id: m.id,
                      text: m.text,
                      senderName: m.senderName,
                      createdAt: m.createdAt,
                    ),
              ],
            );
      });
    });
  }

  @override
  void dispose() {
    _searchSoon?.cancel();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EdgeFieldBar(
              field: RoundField(
                controller: _query,
                hintText: 'Search messages',
                autofocus: true,
                onChanged: (_) {
                  setState(() {});
                  _onQueryChanged();
                },
              ),
            ),
            Expanded(child: _results(context)),
          ],
        ),
      ),
    );
  }

  Widget _results(BuildContext context) {
    final colors = context.colorTheme;
    return FutureBuilder<List<_SearchItem>>(
      future: _messages,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _Hint(
            title: 'Could not search',
            subtitle: 'Check the internet and try again',
          );
        }
        if (!snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(color: colors.secondary),
          );
        }

        final query = _query.text.trim().toLowerCase();
        // Until there is something to look for.
        if (query.length < 2) {
          return const _Hint(
            title: 'Search this chat',
            subtitle: 'Find any message by a word in it',
            icon: true,
          );
        }

        final results = snapshot.data!
            .where((m) => m.text.toLowerCase().contains(query))
            .toList();
        if (results.isEmpty) {
          return const _Hint(
            title: 'Nothing found',
            subtitle: 'Try another word',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: results.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, indent: 20, color: colors.border),
          itemBuilder: (context, index) => _ResultTile(
            item: results[index],
            query: query,
            onTap: () => Navigator.of(context).pop(results[index].id),
          ),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.item,
    required this.query,
    required this.onTap,
  });

  final _SearchItem item;
  final String query;
  final VoidCallback onTap;

  String _date(BuildContext context) {
    final time = item.createdAt;
    if (time == null) return '';
    final now = DateTime.now();
    if (DateUtils.isSameDay(time, now)) {
      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    return MaterialLocalizations.of(context).formatShortMonthDay(time);
  }

  /// The text around the first match, with the match in bold.
  TextSpan _snippet(TextStyle base, Color accent) {
    final text = item.text.replaceAll('\n', ' ');
    final start = text.toLowerCase().indexOf(query);
    if (start < 0) return TextSpan(text: text, style: base);

    // Long texts start a little before the match so it stays visible.
    final from = start > 30 ? start - 20 : 0;
    final end = start + query.length;
    return TextSpan(
      style: base,
      children: [
        if (from > 0) const TextSpan(text: '…'),
        TextSpan(text: text.substring(from, start)),
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(fontWeight: FontWeight.w700, color: accent),
        ),
        TextSpan(text: text.substring(end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  _date(context),
                  style: text.bodySmall.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text.rich(
              _snippet(
                text.bodyLarge.copyWith(
                  fontSize: 15,
                  color: colors.textSecondary,
                ),
                colors.secondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A calm empty state in the middle of the screen: a title and a softer
/// line under it, with a search mark when asked.
class _Hint extends StatelessWidget {
  const _Hint({required this.title, required this.subtitle, this.icon = false});

  final String title;
  final String subtitle;
  final bool icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return Center(
      child: Padding(
        // A little above the middle, where the keyboard leaves room.
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon) ...[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.search, size: 26, color: colors.secondary),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.titleSmall.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: text.bodyLarge.copyWith(
                fontSize: 15,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
