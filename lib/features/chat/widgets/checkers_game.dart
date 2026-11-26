import 'package:sinai/api/current_user.dart';
import 'package:sinai/features/chat/widgets/game_store.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/color_theme.dart';

/// One step of a move: from one square to another, maybe taking a piece.
class CheckersStep {
  const CheckersStep(this.from, this.to, [this.taken]);

  final int from;
  final int to;
  final int? taken;
}

/// Checkers by Russian rules: men move forward and take in every
/// direction, kings fly along diagonals, taking is compulsory and goes on
/// while it can, and a man reaching the far row is crowned at once.
///
/// The board is 64 characters, row 0 on top: '.' empty, 'w'/'b' men,
/// 'W'/'B' kings. White starts at the bottom and moves first.
class CheckersGame {
  const CheckersGame({
    this.raw = const {},
    required this.board,
    required this.white,
    required this.black,
    required this.turn,
    required this.chain,
    required this.from,
    required this.to,
    required this.result,
  });

  final String board;
  final String white;
  final String? black;

  /// 'w' or 'b'.
  final String turn;

  /// The square of a piece in the middle of a multiple capture, which
  /// must keep taking.
  final int? chain;

  /// The last step, to highlight it.
  final int? from;
  final int? to;

  /// null while playing, then 'w' or 'b' (the winner).
  final String? result;

  /// The game as stored, so a move can write it back whole.
  final Map<String, dynamic> raw;

  bool get isOver => result != null;

  static String get initialBoard {
    final cells = List.filled(64, '.');
    for (var i = 0; i < 64; i++) {
      final row = i ~/ 8, col = i % 8;
      if ((row + col).isOdd) {
        if (row < 3) cells[i] = 'b';
        if (row > 4) cells[i] = 'w';
      }
    }
    return cells.join();
  }

  static CheckersGame? fromChat(Map<String, dynamic>? chat) {
    final game = chat?['game'];
    if (game is! Map || game['type'] != 'checkers') return null;
    final board = game['board'] as String?;
    final white = game['white'] as String?;
    if (board == null || board.length != 64 || white == null) return null;
    return CheckersGame(
      raw: Map<String, dynamic>.from(game),
      board: board,
      white: white,
      black: game['black'] as String?,
      turn: game['turn'] as String? ?? 'w',
      chain: (game['chain'] as num?)?.toInt(),
      from: (game['from'] as num?)?.toInt(),
      to: (game['to'] as num?)?.toInt(),
      result: game['result'] as String?,
    );
  }

  String? colorOf(String uid) {
    if (uid == white) return 'w';
    if (black == null || black == uid) return 'b';
    return null;
  }

  bool isTurnOf(String uid) => !isOver && colorOf(uid) == turn;

  static bool _isOwn(String cell, String side) => cell.toLowerCase() == side;
  static bool _isKing(String cell) => cell == 'W' || cell == 'B';
  static bool _onBoard(int row, int col) =>
      row >= 0 && row < 8 && col >= 0 && col < 8;

  static const _dirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)];

  /// Captures the piece on [square] can make.
  static List<CheckersStep> _captures(String board, int square) {
    final piece = board[square];
    final side = piece.toLowerCase();
    final steps = <CheckersStep>[];
    final r0 = square ~/ 8, c0 = square % 8;
    for (final (dr, dc) in _dirs) {
      if (_isKing(piece)) {
        var r = r0 + dr, c = c0 + dc;
        while (_onBoard(r, c) && board[r * 8 + c] == '.') {
          r += dr;
          c += dc;
        }
        if (!_onBoard(r, c)) continue;
        final cell = board[r * 8 + c];
        if (_isOwn(cell, side)) continue;
        final taken = r * 8 + c;
        r += dr;
        c += dc;
        while (_onBoard(r, c) && board[r * 8 + c] == '.') {
          steps.add(CheckersStep(square, r * 8 + c, taken));
          r += dr;
          c += dc;
        }
      } else {
        final r1 = r0 + dr, c1 = c0 + dc, r2 = r0 + 2 * dr, c2 = c0 + 2 * dc;
        if (!_onBoard(r2, c2)) continue;
        final over = board[r1 * 8 + c1];
        if (over != '.' && !_isOwn(over, side) && board[r2 * 8 + c2] == '.') {
          steps.add(CheckersStep(square, r2 * 8 + c2, r1 * 8 + c1));
        }
      }
    }
    return steps;
  }

  /// Plain moves the piece on [square] can make.
  static List<CheckersStep> _slides(String board, int square) {
    final piece = board[square];
    final steps = <CheckersStep>[];
    final r0 = square ~/ 8, c0 = square % 8;
    for (final (dr, dc) in _dirs) {
      if (_isKing(piece)) {
        var r = r0 + dr, c = c0 + dc;
        while (_onBoard(r, c) && board[r * 8 + c] == '.') {
          steps.add(CheckersStep(square, r * 8 + c));
          r += dr;
          c += dc;
        }
      } else {
        // Men only step forward: up for white, down for black.
        if (dr != (piece == 'w' ? -1 : 1)) continue;
        final r = r0 + dr, c = c0 + dc;
        if (_onBoard(r, c) && board[r * 8 + c] == '.') {
          steps.add(CheckersStep(square, r * 8 + c));
        }
      }
    }
    return steps;
  }

  /// Every legal step for the side to move. Taking is compulsory.
  List<CheckersStep> legalSteps() {
    if (chain != null) return _captures(board, chain!);
    final captures = <CheckersStep>[];
    final slides = <CheckersStep>[];
    for (var i = 0; i < 64; i++) {
      if (!_isOwn(board[i], turn)) continue;
      captures.addAll(_captures(board, i));
      if (captures.isEmpty) slides.addAll(_slides(board, i));
    }
    return captures.isNotEmpty ? captures : slides;
  }

  static Future<void> start(String chatCode) => GameStore.replace(chatCode, {
        // Who did what last, for the notification to the others.
        'by': currentUserId()!,
        'event': 'start',
        'type': 'checkers',
        'pick': 'checkers',
        'board': initialBoard,
        'white': currentUserId()!,
        'black': null,
        'turn': 'w',
        'chain': null,
        'from': null,
        'to': null,
        'result': null,
      });

  /// Plays a move on [game], the position on screen. A plain write, not
  /// a transaction: Firestore shows it at once and syncs in the background,
  /// so the board doesn't wait for the network.
  static Future<void> move(
      String chatCode, CheckersGame game, int from, int to) {
    final uid = currentUserId()!;
    return Future(() async {
      if (!game.isTurnOf(uid)) return;
      final step = game
          .legalSteps()
          .where((s) => s.from == from && s.to == to)
          .firstOrNull;
      if (step == null) return;

      final cells = game.board.split('');
      var piece = cells[from];
      cells[from] = '.';
      if (step.taken != null) cells[step.taken!] = '.';
      final row = to ~/ 8;
      if (piece == 'w' && row == 0) piece = 'W';
      if (piece == 'b' && row == 7) piece = 'B';
      cells[to] = piece;
      final board = cells.join();

      // A capture goes on while the same piece can take again.
      final goesOn = step.taken != null && _captures(board, to).isNotEmpty;
      final next = goesOn ? game.turn : (game.turn == 'w' ? 'b' : 'w');
      final after = CheckersGame(
        board: board,
        white: game.white,
        black: game.black,
        turn: next,
        chain: goesOn ? to : null,
        from: from,
        to: to,
        result: null,
      );
      // Whoever can't move loses.
      final String? result =
          !goesOn && after.legalSteps().isEmpty ? game.turn : null;

      await GameStore.change(chatCode, game.raw, {
        'by': uid,
        'event': 'move',
        'board': board,
        if (game.turn == 'b' && game.black == null) 'black': uid,
        'turn': next,
        'chain': goesOn ? to : null,
        'from': from,
        'to': to,
        'result': result,
      });
    });
  }
}

/// The checkers board with whose turn it is. Turned around for black.
class CheckersBoardView extends StatefulWidget {
  const CheckersBoardView({
    super.key,
    required this.chatCode,
    required this.game,
    required this.size,
  });

  final String chatCode;
  final CheckersGame game;
  final double size;

  @override
  State<CheckersBoardView> createState() => _CheckersBoardViewState();
}

class _CheckersBoardViewState extends State<CheckersBoardView> {
  static const _light = Color(0xFFF0D9B5);
  static const _dark = Color(0xFFB58863);

  int? _selected;
  Set<int> _targets = const {};

  @override
  void didUpdateWidget(CheckersBoardView old) {
    super.didUpdateWidget(old);
    if (old.game.board != widget.game.board) {
      _selected = null;
      _targets = const {};
      _selectChain();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectChain();
  }

  /// In the middle of a capture, the capturing piece stays picked.
  void _selectChain() {
    final game = widget.game;
    final uid = currentUserId() ?? '';
    if (game.chain != null && game.isTurnOf(uid)) {
      _selected = game.chain;
      _targets = {for (final s in game.legalSteps()) s.to};
    }
  }

  void _tap(int square) {
    final game = widget.game;
    final uid = currentUserId() ?? '';
    if (_selected != null && _targets.contains(square)) {
      CheckersGame.move(widget.chatCode, widget.game, _selected!, square)
          .catchError((_) {});
      setState(() {
        _selected = null;
        _targets = const {};
      });
      return;
    }
    if (game.chain != null) return;
    final steps =
        game.isTurnOf(uid) ? game.legalSteps() : const <CheckersStep>[];
    final mine = steps.where((s) => s.from == square);
    setState(() {
      if (mine.isEmpty || square == _selected) {
        _selected = null;
        _targets = const {};
      } else {
        _selected = square;
        _targets = {for (final s in mine) s.to};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final uid = currentUserId() ?? '';
    final game = widget.game;
    final mine = game.colorOf(uid);
    final flipped = mine == 'b';
    final cell = widget.size / 8;

    final String status;
    if (game.result != null) {
      status = mine == null
          ? '${game.result == 'w' ? 'White' : 'Black'} won'
          : game.result == mine
              ? 'You won! 🎉'
              : 'You lost';
    } else if (mine == null) {
      status = 'Watching';
    } else if (game.turn == mine) {
      status = game.chain != null ? 'Keep taking' : 'Your turn';
    } else {
      status = game.black == null && game.turn == 'b'
          ? 'Waiting for a player'
          : 'Their turn';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          status,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
            dimension: widget.size,
            child: Column(
              children: [
                for (var row = 0; row < 8; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 8; col++)
                        _square(
                          flipped ? (7 - row) * 8 + (7 - col) : row * 8 + col,
                          cell,
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _square(int square, double size) {
    final game = widget.game;
    final piece = game.board[square];
    final isDark = (square ~/ 8 + square % 8).isOdd;
    var color = isDark ? _dark : _light;
    if (square == game.from || square == game.to) {
      color = Color.lerp(color, const Color(0xFFCDD26A), 0.6)!;
    }
    if (square == _selected) {
      color = Color.lerp(color, const Color(0xFF7FA650), 0.7)!;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(square),
      child: Container(
        width: size,
        height: size,
        color: color,
        alignment: Alignment.center,
        child: piece != '.'
            ? _Disc(piece: piece, size: size)
            : _targets.contains(square)
                ? Container(
                    width: size * 0.3,
                    height: size * 0.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withAlpha(45),
                    ),
                  )
                : null,
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({required this.piece, required this.size});

  final String piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final white = piece.toLowerCase() == 'w';
    final king = piece == 'W' || piece == 'B';
    final d = size * 0.78;
    return Container(
      width: d,
      height: d,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: white ? const Color(0xFFF7F3EC) : const Color(0xFF2B2420),
        border: Border.all(
          color: white ? const Color(0xFF8A7B6A) : Colors.black,
          width: size * 0.05,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: king
          ? Text(
              '♛︎',
              style: TextStyle(
                fontSize: d * 0.55,
                height: 1,
                color:
                    white ? const Color(0xFF8A6A2A) : const Color(0xFFE1B866),
              ),
            )
          : null,
    );
  }
}
