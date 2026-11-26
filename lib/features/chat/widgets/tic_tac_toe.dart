import 'package:sinai/api/current_user.dart';
import 'package:sinai/features/chat/widgets/game_store.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/color_theme.dart';

/// A game of tic-tac-toe kept on the chat document, so every member sees
/// the same board. Whoever starts plays X; the first other member to move
/// plays O.
class TicTacToe {
  const TicTacToe({
    this.raw = const {},
    required this.board,
    required this.x,
    required this.o,
    required this.turn,
    required this.winner,
    required this.line,
  });

  /// Nine cells, each '', 'x' or 'o'.
  final List<String> board;
  final String x;
  final String? o;

  /// 'x' or 'o'.
  final String turn;

  /// null while playing, then 'x', 'o' or 'draw'.
  final String? winner;

  /// The three winning cells.
  final List<int>? line;

  /// The game as stored, so a move can write it back whole.
  final Map<String, dynamic> raw;

  bool get isOver => winner != null;

  static TicTacToe? fromChat(Map<String, dynamic>? chat) {
    final game = chat?['game'];
    if (game is! Map || (game['type'] ?? 'ttt') != 'ttt') return null;
    final board = (game['board'] as List?)?.cast<String>();
    final x = game['x'] as String?;
    if (board == null || board.length != 9 || x == null) return null;
    return TicTacToe(
      raw: Map<String, dynamic>.from(game),
      board: board,
      x: x,
      o: game['o'] as String?,
      turn: game['turn'] as String? ?? 'x',
      winner: game['winner'] as String?,
      line: (game['line'] as List?)?.cast<int>(),
    );
  }

  /// The mark [uid] plays, or null if they can't play in this game.
  String? markOf(String uid) {
    if (uid == x) return 'x';
    if (o == null || o == uid) return 'o';
    return null;
  }

  /// Whether the game is waiting on [uid] to move.
  bool isTurnOf(String uid) => !isOver && markOf(uid) == turn;

  static const _lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  static Future<void> start(String chatCode) => GameStore.replace(chatCode, {
        // Who did what last, for the notification to the others.
        'by': currentUserId()!,
        'event': 'start',
        'type': 'ttt',
        'pick': 'ttt',
        'board': List.filled(9, ''),
        'x': currentUserId()!,
        'o': null,
        'turn': 'x',
        'winner': null,
        'line': null,
      });

  /// Puts the user's mark on [cell], if it's their turn and the cell is free.
  /// Plays a move on [game], the position on screen. A plain write, not
  /// a transaction: Firestore shows it at once and syncs in the background,
  /// so the board doesn't wait for the network.
  static Future<void> move(String chatCode, TicTacToe game, int cell) {
    final uid = currentUserId()!;
    return Future(() async {
      if (!game.isTurnOf(uid) || game.board[cell] != '') {
        return;
      }
      final mark = game.turn;
      final board = [...game.board]..[cell] = mark;
      List<int>? line;
      for (final l in _lines) {
        if (l.every((i) => board[i] == mark)) line = l;
      }
      final winner = line != null
          ? mark
          : board.every((c) => c != '')
              ? 'draw'
              : null;
      await GameStore.change(chatCode, game.raw, {
        'by': uid,
        'event': 'move',
        'board': board,
        if (mark == 'o' && game.o == null) 'o': uid,
        'turn': mark == 'x' ? 'o' : 'x',
        'winner': winner,
        'line': line,
      });
    });
  }
}

/// The board with a line about whose turn it is, shown in the notch.
class TicTacToeBoard extends StatelessWidget {
  const TicTacToeBoard({
    super.key,
    required this.chatCode,
    this.game,
    this.armed = false,
  });

  final String chatCode;
  final TicTacToe? game;

  /// Pulled far enough that letting go starts a new game.
  final bool armed;

  static const _cell = 46.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final uid = currentUserId() ?? '';
    final game = this.game;

    final hint = Text(
      armed ? 'Release to start' : 'Pull to start a game',
      style: _caption(colors).copyWith(
        color: armed ? colors.secondary : colors.textSecondary,
      ),
    );

    if (game == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Tic-tac-toe', style: _caption(colors)),
            const SizedBox(height: 4),
            hint,
          ],
        ),
      );
    }

    final mine = game.markOf(uid);
    final String status;
    if (game.winner == 'draw') {
      status = 'Draw';
    } else if (game.winner != null) {
      status = game.winner == mine ? 'You won! 🎉' : 'You lost';
    } else if (mine == null) {
      status = 'Watching';
    } else if (game.turn == mine) {
      status = 'Your turn';
    } else {
      status = game.o == null ? 'Waiting for a player' : 'Their turn';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(status, style: _caption(colors)),
          const SizedBox(height: 8),
          SizedBox(
            width: _cell * 3,
            height: _cell * 3,
            child: GridView.count(
              crossAxisCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                for (var i = 0; i < 9; i++)
                  _Cell(
                    mark: game.board[i],
                    highlighted: game.line?.contains(i) ?? false,
                    right: i % 3 < 2,
                    bottom: i < 6,
                    onTap: game.isTurnOf(uid) && game.board[i] == ''
                        ? () =>
                            TicTacToe.move(chatCode, game, i).catchError((_) {})
                        : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _caption(ColorTheme colors) => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.mark,
    required this.highlighted,
    required this.right,
    required this.bottom,
    required this.onTap,
  });

  final String mark;
  final bool highlighted;
  final bool right;
  final bool bottom;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final line = BorderSide(color: colors.border, width: 1.5);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: highlighted ? colors.secondary.withAlpha(60) : null,
          border: Border(
            right: right ? line : BorderSide.none,
            bottom: bottom ? line : BorderSide.none,
          ),
        ),
        alignment: Alignment.center,
        child: AnimatedScale(
          scale: mark.isEmpty ? 0 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Text(
            mark == 'x'
                ? '✕'
                : mark == 'o'
                    ? '◯'
                    : '',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: mark == 'x' ? colors.textPrimary : colors.secondary,
            ),
          ),
        ),
      ),
    );
  }
}
