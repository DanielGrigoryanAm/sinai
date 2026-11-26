import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sinai/features/chat/widgets/watch_together.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// A video a link points to that can play right in the chat.
sealed class LinkVideo {
  const LinkVideo();

  /// The playable video behind [uri], if its site is one we know.
  static LinkVideo? of(Uri uri) {
    final link = uri.toString();
    if (youtubeId(link) case final id?) return YoutubeVideo(id);
    final vimeo = RegExp(r'vimeo\.com/(?:video/)?(\d+)', caseSensitive: false)
        .firstMatch(link);
    if (vimeo != null) return VimeoVideo(vimeo.group(1)!, uri);
    return null;
  }

  Future<String?> thumbnail();
}

class YoutubeVideo extends LinkVideo {
  const YoutubeVideo(this.id);
  final String id;

  @override
  Future<String?> thumbnail() async =>
      'https://i.ytimg.com/vi/$id/hqdefault.jpg';
}

class VimeoVideo extends LinkVideo {
  const VimeoVideo(this.id, this.uri);
  final String id;
  final Uri uri;

  static final _thumbs = <String, Future<String?>>{};

  @override
  Future<String?> thumbnail() => _thumbs.putIfAbsent(id, () async {
        try {
          final r = await http
              .get(Uri.https('vimeo.com', '/api/oembed.json',
                  {'url': 'https://vimeo.com/$id'}))
              .timeout(const Duration(seconds: 6));
          if (r.statusCode != 200) return null;
          return (jsonDecode(r.body) as Map)['thumbnail_url'] as String?;
        } catch (_) {
          return null;
        }
      });
}

/// The video of a link, to watch alone right in the message: a picture
/// with a play button, and the site's own player once tapped. Players load
/// only on a tap, so a chat full of links stays light.
class LinkPlayer extends StatefulWidget {
  const LinkPlayer({super.key, required this.video});

  final LinkVideo video;

  @override
  State<LinkPlayer> createState() => _LinkPlayerState();
}

class _LinkPlayerState extends State<LinkPlayer> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    // As wide as the bubble lets it be, whatever the text's width.
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        width: constraints.maxWidth,
        margin: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _playing
                ? switch (widget.video) {
                    YoutubeVideo(:final id) => _YoutubeInline(id: id),
                    VimeoVideo(:final id) => _VimeoInline(id: id),
                  }
                : _Poster(
                    video: widget.video,
                    onTap: () => setState(() => _playing = true),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.video, required this.onTap});

  final LinkVideo video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          FutureBuilder<String?>(
            future: video.thumbnail(),
            builder: (context, snap) => snap.data == null
                ? const SizedBox.shrink()
                : CachedNetworkImage(
                    imageUrl: snap.data!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
          ),
          Center(
            child: Container(
              width: 52,
              height: 36,
              decoration: BoxDecoration(
                color: video is YoutubeVideo
                    ? const Color(0xFFFF0000)
                    : const Color(0xFF1AB7EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 28),
            ),
          ),
        ],
      ),
    );
  }
}

class _YoutubeInline extends StatefulWidget {
  const _YoutubeInline({required this.id});
  final String id;

  @override
  State<_YoutubeInline> createState() => _YoutubeInlineState();
}

class _YoutubeInlineState extends State<_YoutubeInline> {
  late final _controller = YoutubePlayerController.fromVideoId(
    videoId: widget.id,
    autoPlay: true,
    params: const YoutubePlayerParams(
      showFullscreenButton: true,
      strictRelatedVideos: true,
      playsInline: true,
    ),
  );

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      YoutubePlayer(controller: _controller, aspectRatio: 16 / 9);
}

class _VimeoInline extends StatefulWidget {
  const _VimeoInline({required this.id});
  final String id;

  @override
  State<_VimeoInline> createState() => _VimeoInlineState();
}

class _VimeoInlineState extends State<_VimeoInline> {
  late final WebViewController _web = () {
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          )
        : const PlatformWebViewControllerCreationParams();
    return WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..loadRequest(Uri.parse(
          'https://player.vimeo.com/video/${widget.id}?autoplay=1&playsinline=1'));
  }();

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
