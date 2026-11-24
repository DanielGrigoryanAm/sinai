import 'package:chess/chess.dart' as ch;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/color_theme.dart';

/// A chess game kept on the chat document. Whoever starts plays white; the
/// first other member to move plays black. Pawns always promote to queens.
class ChessGame {
  const ChessGame({
    required this.fen,
    required this.white,
    required this.black,
    required this.from,
    required this.to,
    required this.result,
  });

  /// The position in standard FEN notation.
  final String fen;
  final String white;
  final String? black;

  /// The last move, to highlight it.
  final String? from;
  final String? to;

  /// null while playing, then 'w', 'b' (the winner) or 'draw'.
  final String? result;

  bool get isOver => result != null;

  /// 'w' or 'b'.
  String get turn => fen.split(' ')[1];

  static ChessGame? fromChat(Map<String, dynamic>? chat) {
    final game = chat?['game'];
    if (game is! Map || game['type'] != 'chess') return null;
    final fen = game['fen'] as String?;
    final white = game['white'] as String?;
    if (fen == null || white == null) return null;
    return ChessGame(
      fen: fen,
      white: white,
      black: game['black'] as String?,
      from: game['from'] as String?,
      to: game['to'] as String?,
      result: game['result'] as String?,
    );
  }

  /// 'w' or 'b' for the side [uid] plays, or null if they only watch.
  String? colorOf(String uid) {
    if (uid == white) return 'w';
    if (black == null || black == uid) return 'b';
    return null;
  }

  bool isTurnOf(String uid) => !isOver && colorOf(uid) == turn;

  static DocumentReference<Map<String, dynamic>> _chat(String code) =>
      FirebaseFirestore.instance.collection('chats').doc(code);

  static Future<void> start(String chatCode) => _chat(chatCode).update({
        'game': {
          'type': 'chess',
          'pick': 'chess',
          'fen': ch.Chess().fen,
          'white': FirebaseAuth.instance.currentUser!.uid,
          'black': null,
          'from': null,
          'to': null,
          'result': null,
        },
      });

  static Future<void> move(String chatCode, String from, String to) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = _chat(chatCode);
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final game = fromChat((await tx.get(ref)).data());
      if (game == null || !game.isTurnOf(uid)) return;
      final chess = ch.Chess.fromFEN(game.fen);
      final mover = game.turn;
      if (!chess.move({'from': from, 'to': to, 'promotion': 'q'})) return;
      final String? result = chess.in_checkmate
          ? mover
          : chess.in_draw || chess.in_stalemate
              ? 'draw'
              : null;
      tx.update(ref, {
        'game.fen': chess.fen,
        if (mover == 'b' && game.black == null) 'game.black': uid,
        'game.from': from,
        'game.to': to,
        'game.result': result,
      });
    });
  }
}

/// The chess board with whose turn it is. Turned around for black.
class ChessBoardView extends StatefulWidget {
  const ChessBoardView({
    super.key,
    required this.chatCode,
    required this.game,
    required this.size,
  });

  final String chatCode;
  final ChessGame game;

  /// Width and height of the board.
  final double size;

  @override
  State<ChessBoardView> createState() => _ChessBoardViewState();
}

class _ChessBoardViewState extends State<ChessBoardView> {
  static const _files = 'abcdefgh';
  static const _light = Color(0xFFF0D9B5);
  static const _dark = Color(0xFFB58863);

  String? _selected;
  Set<String> _targets = const {};

  @override
  void didUpdateWidget(ChessBoardView old) {
    super.didUpdateWidget(old);
    if (old.game.fen != widget.game.fen) {
      _selected = null;
      _targets = const {};
    }
  }

  void _tap(String square, ch.Chess chess, String uid) {
    final game = widget.game;
    if (_selected != null && _targets.contains(square)) {
      ChessGame.move(widget.chatCode, _selected!, square).catchError((_) {});
      setState(() {
        _selected = null;
        _targets = const {};
      });
      return;
    }
    final piece = chess.get(square);
    final mine = game.colorOf(uid);
    if (game.isTurnOf(uid) &&
        piece != null &&
        (piece.color == ch.Color.WHITE ? 'w' : 'b') == mine &&
        square != _selected) {
      final moves = chess.moves({'square': square, 'verbose': true});
      setState(() {
        _selected = square;
        _targets = {for (final m in moves) (m as Map)['to'] as String};
      });
    } else {
      setState(() {
        _selected = null;
        _targets = const {};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final game = widget.game;
    final chess = ch.Chess.fromFEN(game.fen);
    final mine = game.colorOf(uid);
    final flipped = mine == 'b';
    final cell = widget.size / 8;

    final String status;
    if (game.result == 'draw') {
      status = 'Draw';
    } else if (game.result != null) {
      status = mine == null
          ? '${game.result == 'w' ? 'White' : 'Black'} won'
          : game.result == mine
              ? 'Checkmate — you won! 🎉'
              : 'Checkmate — you lost';
    } else if (mine == null) {
      status = 'Watching';
    } else if (game.turn == mine) {
      status = chess.in_check ? 'Check! Your turn' : 'Your turn';
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
                          chess,
                          uid,
                          // Rank 8 is on top for white, rank 1 for black.
                          '${_files[flipped ? 7 - col : col]}'
                          '${flipped ? row + 1 : 8 - row}',
                          isDark: (row + col).isOdd,
                          size: cell,
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

  Widget _square(
    ch.Chess chess,
    String uid,
    String square, {
    required bool isDark,
    required double size,
  }) {
    final piece = chess.get(square);
    final lastMove = square == widget.game.from || square == widget.game.to;
    final selected = square == _selected;
    final target = _targets.contains(square);

    var color = isDark ? _dark : _light;
    if (lastMove) color = Color.lerp(color, const Color(0xFFCDD26A), 0.6)!;
    if (selected) color = Color.lerp(color, const Color(0xFF7FA650), 0.7)!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tap(square, chess, uid),
      child: Container(
        width: size,
        height: size,
        color: color,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (piece != null) _Piece(piece: piece, size: size),
            if (target)
              Container(
                width: piece == null ? size * 0.3 : size * 0.9,
                height: piece == null ? size * 0.3 : size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: piece == null ? Colors.black.withAlpha(45) : null,
                  border: piece == null
                      ? null
                      : Border.all(
                          color: Colors.black.withAlpha(45),
                          width: size * 0.08,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Piece extends StatelessWidget {
  const _Piece({required this.piece, required this.size});

  final ch.Piece piece;
  final double size;

  // Solid shapes for both sides, coloured below; the selector keeps iOS
  // from drawing the pawn as an emoji.
  static const _glyphs = {
    'k': '♚',
    'q': '♛',
    'r': '♜',
    'b': '♝',
    'n': '♞',
    'p': '♟',
  };

  @override
  Widget build(BuildContext context) {
    final glyph = '${_glyphs[piece.type.name]!}︎';
    final white = piece.color == ch.Color.WHITE;
    final style = TextStyle(fontSize: size * 0.78, height: 1);
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outline, so white pieces stand out on light squares.
        Text(
          glyph,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.06
              ..color = white ? const Color(0xFF3A2E24) : Colors.black,
          ),
        ),
        Text(
          glyph,
          style: style.copyWith(
            color: white ? Colors.white : const Color(0xFF1E1A17),
          ),
        ),
      ],
    );
  }
}
