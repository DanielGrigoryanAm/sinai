import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

final _urlPattern = RegExp(
  r'(?:https?:\/\/|www\.)[^\s<>"]+[^\s<>".,;:!?)\]]',
  caseSensitive: false,
);

Uri? _toUri(String raw) =>
    Uri.tryParse(raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw);

/// First link in [text], if any.
Uri? firstLink(String text) {
  final match = _urlPattern.firstMatch(text);
  return match == null ? null : _toUri(match.group(0)!);
}

Future<void> openLink(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Message text with tappable links.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, required this.style, this.linkColor});

  final String text;
  final TextStyle style;
  final Color? linkColor;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();

    final matches = _urlPattern.allMatches(widget.text).toList();
    if (matches.isEmpty) return Text(widget.text, style: widget.style);

    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in matches) {
      if (match.start > last) {
        spans.add(TextSpan(text: widget.text.substring(last, match.start)));
      }
      final raw = match.group(0)!;
      final uri = _toUri(raw);
      final recognizer = TapGestureRecognizer()
        ..onTap = uri == null ? null : () => openLink(uri);
      _recognizers.add(recognizer);
      spans.add(TextSpan(
        text: raw,
        recognizer: recognizer,
        style: TextStyle(
          color: widget.linkColor ?? const Color(0xFF1D5FA8),
          decoration: TextDecoration.underline,
          decorationColor: widget.linkColor ?? const Color(0xFF1D5FA8),
        ),
      ));
      last = match.end;
    }
    if (last < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(last)));
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}

/// Title, description and picture a page shares about itself.
class LinkMeta {
  const LinkMeta({this.title, this.description, this.imageUrl});

  final String? title;
  final String? description;
  final String? imageUrl;

  bool get isEmpty => title == null && description == null;
}

final _metaCache = <String, Future<LinkMeta?>>{};

Future<LinkMeta?> _fetchMeta(Uri uri) =>
    _metaCache.putIfAbsent(uri.toString(), () async {
      try {
        final response = await http
            .get(uri, headers: {'User-Agent': 'Mozilla/5.0 (compatible; Bot)'})
            .timeout(const Duration(seconds: 6));
        if (response.statusCode != 200) return null;
        // Only the head matters, and pages can be huge.
        final body = response.body;
        final html = body.length > 200000 ? body.substring(0, 200000) : body;

        String? meta(String key) {
          for (final pattern in [
            RegExp(
              '<meta[^>]+(?:property|name)=["\']$key["\'][^>]*content=["\']([^"\']*)',
              caseSensitive: false,
            ),
            RegExp(
              '<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']$key["\']',
              caseSensitive: false,
            ),
          ]) {
            final value = pattern.firstMatch(html)?.group(1)?.trim();
            if (value != null && value.isNotEmpty) return _unescape(value);
          }
          return null;
        }

        final titleTag = RegExp(r'<title[^>]*>([^<]*)', caseSensitive: false)
            .firstMatch(html)
            ?.group(1)
            ?.trim();
        var image = meta('og:image') ?? meta('twitter:image');
        if (image != null) image = uri.resolve(image).toString();

        final result = LinkMeta(
          title: meta('og:title') ??
              meta('twitter:title') ??
              (titleTag == null || titleTag.isEmpty
                  ? null
                  : _unescape(titleTag)),
          description: meta('og:description') ?? meta('description'),
          imageUrl: image,
        );
        return result.isEmpty ? null : result;
      } catch (_) {
        return null;
      }
    });

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#x27;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

/// Card under a message with the site, title and picture of its link.
class LinkPreview extends StatelessWidget {
  const LinkPreview({super.key, required this.uri, required this.accent});

  final Uri uri;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<LinkMeta?>(
      future: _fetchMeta(uri),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        if (meta == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => openLink(uri),
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
            decoration: BoxDecoration(
              color: accent.withAlpha(22),
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  uri.host.replaceFirst('www.', ''),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                if (meta.title != null)
                  Text(
                    meta.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B2030),
                    ),
                  ),
                if (meta.description != null)
                  Text(
                    meta.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: const Color(0xFF1B2030).withAlpha(170),
                    ),
                  ),
                if (meta.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: meta.imageUrl!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
