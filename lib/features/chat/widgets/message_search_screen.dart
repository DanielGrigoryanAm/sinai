import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Searches a chat's messages by text. Pops with the id of the tapped
/// message, so the chat can scroll to it.
///
/// Firestore has no full-text search, so the chat's messages are loaded
/// once when the screen opens and filtered on the phone.
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
  late final Future<List<_SearchItem>> _messages = _load();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<List<_SearchItem>> _load() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatCode)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .get();

    return [
      for (final doc in snapshot.docs)
        if ((doc.data()['text'] as String?)?.trim().isNotEmpty ?? false)
          _SearchItem(
            id: doc.id,
            text: doc.data()['text'] as String,
            senderName: (doc.data()['senderName'] as String?) ?? 'Guest',
            createdAt: (doc.data()['createdAt'] as Timestamp?)?.toDate(),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: TextField(
          controller: _query,
          autofocus: true,
          cursorColor: colors.secondary,
          textInputAction: TextInputAction.search,
          style: context.textTheme.bodyLarge,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search messages',
            hintStyle: context.textTheme.bodyLarge
                .copyWith(color: colors.textSecondary),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (_query.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () => setState(_query.clear),
            ),
        ],
      ),
      body: FutureBuilder<List<_SearchItem>>(
        future: _messages,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _Hint('Could not load messages');
          }
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: colors.secondary),
            );
          }

          final query = _query.text.trim().toLowerCase();
          if (query.length < 2) {
            return const _Hint('Type at least 2 letters');
          }

          final results = snapshot.data!
              .where((m) => m.text.toLowerCase().contains(query))
              .toList();
          if (results.isEmpty) return const _Hint('Nothing found');

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
      ),
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

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: context.textTheme.bodyLarge
            .copyWith(color: context.colorTheme.textSecondary),
      ),
    );
  }
}
