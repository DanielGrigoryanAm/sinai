import 'package:chess/chess.dart' as ch;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/color_theme.dart';

/// A chess game kept on the chat document. Whoever starts plays white; the
/// first other member to move plays black.
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
          // Who did what last, for the notification to the others.
          'by': FirebaseAuth.instance.currentUser!.uid,
          'event': 'start',
          'at': FieldValue.serverTimestamp(),
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

  /// Plays a move on [game], the position on screen. A plain write, not
  /// a transaction: Firestore shows it at once and syncs in the background,
  /// so the board doesn't wait for the network.
  static Future<void> move(
    String chatCode,
    ChessGame game,
    String from,
    String to, [
    String promotion = 'q',
  ]) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = _chat(chatCode);
    return Future(() async {
      if (!game.isTurnOf(uid)) return;
      final chess = ch.Chess.fromFEN(game.fen);
      final mover = game.turn;
      if (!chess.move({'from': from, 'to': to, 'promotion': promotion})) return;
      final String? result = chess.in_checkmate
          ? mover
          : chess.in_draw || chess.in_stalemate
              ? 'draw'
              : null;
      await ref.update({
        'game.by': uid,
        'game.event': 'move',
        'game.at': FieldValue.serverTimestamp(),
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
      final from = _selected!;
      setState(() {
        _selected = null;
        _targets = const {};
      });
      _play(chess, from, square);
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

  /// Plays [from]→[to], first asking which piece a pawn on the last rank
  /// becomes.
  Future<void> _play(ch.Chess chess, String from, String to) async {
    final piece = chess.get(from);
    final white = piece?.color == ch.Color.WHITE;
    var promotion = 'q';
    if (piece?.type == ch.PieceType.PAWN && to.endsWith(white ? '8' : '1')) {
      final picked = await showDialog<String>(
        context: context,
        builder: (_) => _PromotionDialog(white: white),
      );
      if (picked == null || !mounted) return;
      promotion = picked;
    }
    ChessGame.move(widget.chatCode, widget.game, from, to, promotion)
        .catchError((_) {});
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

  // Flaticon UIcons solid rounded, one glyph per piece.
  static const _glyphs = {
    'k': 0xe3e8,
    'q': 0xe3ef,
    'r': 0xe3f1,
    'b': 0xe3e4,
    'n': 0xe3ea,
    'p': 0xe3ec,
  };

  @override
  Widget build(BuildContext context) {
    final glyph = String.fromCharCode(_glyphs[piece.type.name]!);
    final white = piece.color == ch.Color.WHITE;
    final style = TextStyle(
      fontFamily: 'UiconsSolid',
      fontSize: size * 0.55,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        // Outline, so white pieces stand out on light squares.
        Text(
          glyph,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.07
              ..strokeJoin = StrokeJoin.round
              ..color =
                  white ? const Color(0xFF3A2E24) : const Color(0xFF0F0C0A),
          ),
        ),
        Text(
          glyph,
          style: style.copyWith(
            color: white ? Colors.white : const Color(0xFF2B2420),
          ),
        ),
      ],
    );
  }
}

/// Asks which piece a pawn reaching the last rank becomes.
class _PromotionDialog extends StatelessWidget {
  const _PromotionDialog({required this.white});

  final bool white;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Dialog(
      backgroundColor: colors.backgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Promote to',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                for (final type in const [
                  ch.PieceType.QUEEN,
                  ch.PieceType.ROOK,
                  ch.PieceType.BISHOP,
                  ch.PieceType.KNIGHT,
                ])
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(type.name),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0D9B5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: _Piece(
                        piece: ch.Piece(
                          type,
                          white ? ch.Color.WHITE : ch.Color.BLACK,
                        ),
                        size: 56,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
