import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/widgets/chat_games.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Picks the game a pull on the notch starts. The pick belongs to the chat,
/// so every member gets the same game.
class MiniGamesScreen extends StatelessWidget {
  const MiniGamesScreen({super.key, required this.chatCode});

  final String chatCode;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(AppIcons.arrowLeft, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Mini games',
          style: context.textTheme.titleLarge.copyWith(
            color: colors.textPrimary,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(chatCode)
            .snapshots(),
        builder: (context, snapshot) {
          final picked = ChatGameType.pickedIn(snapshot.data?.data());
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Pull the notch down and let go to start a game. Everyone '
                'in this chat gets the game picked here.',
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
              const SizedBox(height: 16),
              for (final type in ChatGameType.values) ...[
                _GameChoice(
                  type: type,
                  selected: type == picked,
                  onTap: () => ChatGameType.pick(
                    chatCode,
                    snapshot.data?.data(),
                    type,
                  ).catchError((_) {}),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GameChoice extends StatelessWidget {
  const _GameChoice({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final ChatGameType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colors.secondary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.secondary.withAlpha(selected ? 70 : 30),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                switch (type) {
                  ChatGameType.chess => '\u265E\uFE0E',
                  ChatGameType.checkers => '\u26C2\uFE0E',
                  ChatGameType.ticTacToe => '✕◯',
                },
                style: TextStyle(
                  fontSize: type == ChatGameType.ticTacToe ? 18 : 30,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: context.textTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    switch (type) {
                      ChatGameType.chess =>
                        'The full game. The board fills the notch.',
                      ChatGameType.checkers =>
                        'Russian rules: taking is a must, kings fly.',
                      ChatGameType.ticTacToe => 'Quick game on a 3×3 board.',
                    },
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(AppIcons.check, color: colors.secondary),
            ),
          ],
        ),
      ),
    );
  }
}
