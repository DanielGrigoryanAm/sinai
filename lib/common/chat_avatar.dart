import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/api/media_url.dart';

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

    // The photo is clipped to a circle by itself and the white ring is
    // drawn over it, so a photo's square corners never show at the edge.
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFECEDF2),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: ClipOval(
        child: url == null || url.isEmpty
            ? letter
            : CachedNetworkImage(
                imageUrl: mediaUrl(url).url,
                cacheKey: mediaUrl(url).cacheKey,
                fit: BoxFit.cover,
                width: size,
                height: size,
                memCacheWidth:
                    (size * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (_, __) => letter,
                errorWidget: (_, __, ___) => letter,
              ),
      ),
    );
  }
}
