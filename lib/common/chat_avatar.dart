import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';

/// Round avatar: the photo when there is one, otherwise the first letter
/// of [title] on a grey circle.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.title,
    this.photoUrl,
    this.size = 56,
  });

  final String title;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final initial =
        trimmed.isEmpty ? '#' : trimmed.characters.first.toUpperCase();
    final letter = Center(
      child: Text(
        initial,
        style: context.textTheme.titleSmall.copyWith(
          fontSize: size * 0.34,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF6B7080),
        ),
      ),
    );
    final url = photoUrl;

    return Container(
      width: size,
      height: size,
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
      clipBehavior: Clip.antiAlias,
      child: url == null || url.isEmpty
          ? letter
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, __) => letter,
              errorWidget: (_, __, ___) => letter,
            ),
    );
  }
}
