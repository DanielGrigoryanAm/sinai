import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/features/chat/widgets/checkers_game.dart';
import 'package:sinai/features/chat/widgets/chess_game.dart';
import 'package:sinai/features/chat/widgets/tic_tac_toe.dart';
import 'package:sinai/theme/color_theme.dart';

enum ChatGameType {
  ticTacToe('ttt', 'Tic-tac-toe'),
  chess('chess', 'Chess'),
  checkers('checkers', 'Checkers');

  /// Played on a full 8×8 board, which needs the notch's whole width.
  bool get isWide => this != ticTacToe;

  const ChatGameType(this.id, this.label);

  final String id;
  final String label;

  /// The game a pull on the notch starts in [chat], the same for every
  /// member. Chess unless someone picked otherwise.
  static ChatGameType pickedIn(Map<String, dynamic>? chat) {
    final game = chat?['game'];
    final id = game is Map ? game['pick'] : null;
    return values.firstWhere((t) => t.id == id, orElse: () => chess);
  }

  /// Sets the game the notch starts for everyone in the chat. Kept inside
  /// the game field, which every member may change. A game of another kind
  /// still on the board is put away, so the notch shows the new pick.
  static Future<void> pick(
    String chatCode,
    Map<String, dynamic>? chat,
    ChatGameType type,
  ) {
    final game = chat?['game'];
    final current = game is Map
        ? (game['type'] ?? (game['board'] == null ? null : 'ttt'))
        : null;
    return FirebaseFirestore.instance.collection('chats').doc(chatCode).update(
          current == null || current == type.id
              ? {'game.pick': type.id}
              : {
                  'game': {'pick': type.id},
                },
        );
  }
}

/// The game shown in the pulled-down notch: the one being played, or a
/// picker for the next one with a pull-to-start hint.
class ChatGames extends StatelessWidget {
  const ChatGames({
    super.key,
    required this.chatCode,
    required this.chat,
    required this.armed,
    required this.chessSize,
  });

  final String chatCode;

  /// The chat document's data.
  final Map<String, dynamic>? chat;

  /// Pulled far enough that letting go starts a game.
  final bool armed;
  final double chessSize;

  /// The game being played, if one is and isn't finished.
  static ChatGameType? playing(Map<String, dynamic>? chat) {
    if (TicTacToe.fromChat(chat)?.isOver == false) {
      return ChatGameType.ticTacToe;
    }
    if (ChessGame.fromChat(chat)?.isOver == false) return ChatGameType.chess;
    if (CheckersGame.fromChat(chat)?.isOver == false) {
      return ChatGameType.checkers;
    }
    return null;
  }

  /// The game on screen: the one being played, else the last finished one
  /// if it's what's picked, else the pick.
  static ChatGameType shown(Map<String, dynamic>? chat) =>
      playing(chat) ?? ChatGameType.pickedIn(chat);

  /// Whether the game waits on the current user.
  static bool waitsOnMe(Map<String, dynamic>? chat) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return (TicTacToe.fromChat(chat)?.isTurnOf(uid) ?? false) ||
        (ChessGame.fromChat(chat)?.isTurnOf(uid) ?? false) ||
        (CheckersGame.fromChat(chat)?.isTurnOf(uid) ?? false);
  }

  /// Starts the game being played over again.
  static Future<void> restart(String chatCode, Map<String, dynamic>? chat) =>
      _start(chatCode, playing(chat) ?? ChatGameType.pickedIn(chat));

  static Future<void> _start(String chatCode, ChatGameType type) =>
      switch (type) {
        ChatGameType.ticTacToe => TicTacToe.start(chatCode),
        ChatGameType.chess => ChessGame.start(chatCode),
        ChatGameType.checkers => CheckersGame.start(chatCode),
      };

  /// Ends the game without a result, keeping the pick.
  static Future<void> cancel(String chatCode, Map<String, dynamic>? chat) =>
      FirebaseFirestore.instance.collection('chats').doc(chatCode).update({
        'game': {'pick': ChatGameType.pickedIn(chat).id},
      });

  /// Starts the picked game, keeping the pick.
  static Future<void> start(String chatCode, Map<String, dynamic>? chat) =>
      _start(chatCode, ChatGameType.pickedIn(chat));

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final playing = ChatGames.playing(chat);
    final ttt = TicTacToe.fromChat(chat);
    final chess = ChessGame.fromChat(chat);
    final checkers = CheckersGame.fromChat(chat);
    final type = playing ?? ChatGameType.pickedIn(chat);

    // The finished game stays on screen above the picker, so the result
    // can still be seen.
    Widget? board;
    if (type == ChatGameType.chess && chess != null) {
      board = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: ChessBoardView(chatCode: chatCode, game: chess, size: chessSize),
      );
    } else if (type == ChatGameType.checkers && checkers != null) {
      board = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        child: CheckersBoardView(
          chatCode: chatCode,
          game: checkers,
          size: chessSize,
        ),
      );
    } else if (type == ChatGameType.ticTacToe && ttt != null) {
      board = TicTacToeBoard(chatCode: chatCode, game: ttt);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (board != null) board,
          if (playing == null) ...[
            if (board != null) const SizedBox(height: 10),
            Text(
              ChatGameType.pickedIn(chat).label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              armed ? 'Release to start' : 'Pull to start a game',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: armed ? colors.secondary : colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
