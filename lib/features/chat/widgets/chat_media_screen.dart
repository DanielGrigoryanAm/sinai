import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/widgets/image_viewer_screen.dart';
import 'package:sinai/features/chat/widgets/voice_player.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/api/media_url.dart';
import 'package:sinai/api/chats_api.dart';

/// All photos and voice messages of a chat, newest first.
class ChatMediaScreen extends StatefulWidget {
  const ChatMediaScreen({super.key, required this.chatCode});

  final String chatCode;

  @override
  State<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends State<ChatMediaScreen> {
  /// Messages with [field] set, newest first. Filtering on the field alone
  /// needs no composite index; the order is fixed up here.
  late final Future<List<Map<String, dynamic>>> _photos = _load('imageUrl');
  late final Future<List<Map<String, dynamic>>> _voices = _load('audioUrl');

  Future<List<Map<String, dynamic>>> _load(String field) async {
    final list = await ChatsApi.instance
        .media(widget.chatCode, field == 'imageUrl' ? 'image' : 'voice');
    return [
      for (final m in list)
        {
          'imageUrl': m.imageUrl,
          'audioUrl': m.audioUrl,
          'audioDurationMs': m.audioDurationMs,
          'senderName': m.senderName,
          'createdAt': m.createdAt,
        },
    ];
  }

  @override
  void dispose() {
    VoicePlayer.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colors.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: colors.backgroundPrimary,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(AppIcons.arrowLeft),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Media', style: context.textTheme.titleLarge),
          bottom: TabBar(
            labelColor: colors.textPrimary,
            unselectedLabelColor: colors.textSecondary,
            indicatorColor: colors.secondary,
            tabs: const [Tab(text: 'Photos'), Tab(text: 'Voice')],
          ),
        ),
        body: TabBarView(
          children: [
            _Loaded(
              future: _photos,
              empty: 'No photos yet',
              builder: (items) => GridView.builder(
                padding: const EdgeInsets.all(2),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final url = items[index]['imageUrl'] as String;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ImageViewerScreen(imageUrl: url),
                      ),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: mediaUrl(url).url,
                      cacheKey: mediaUrl(url).cacheKey,
                      memCacheWidth:
                          (140 * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          ColoredBox(color: colors.backgroundSecondary),
                      errorWidget: (_, __, ___) => ColoredBox(
                        color: colors.backgroundSecondary,
                        child: Icon(
                          AppIcons.brokenImage,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            _Loaded(
              future: _voices,
              empty: 'No voice messages yet',
              builder: (items) => ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, indent: 72, color: colors.border),
                itemBuilder: (context, index) =>
                    _VoiceRow(message: items[index]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.future,
    required this.empty,
    required this.builder,
  });

  final Future<List<Map<String, dynamic>>> future;
  final String empty;
  final Widget Function(List<Map<String, dynamic>> items) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Could not load'));
        }
        final items = snapshot.data;
        if (items == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (items.isEmpty) {
          return Center(
            child: Text(
              empty,
              style: TextStyle(color: context.colorTheme.textSecondary),
            ),
          );
        }
        return builder(items);
      },
    );
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.message});

  final Map<String, dynamic> message;

  String _duration(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final url = message['audioUrl'] as String;
    final recorded = Duration(
        milliseconds: (message['audioDurationMs'] as num?)?.toInt() ?? 0);
    final at = message['createdAt'] as DateTime?;
    final localizations = MaterialLocalizations.of(context);
    final when = at == null
        ? ''
        : '${localizations.formatMediumDate(at)}, '
            '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(at), alwaysUse24HourFormat: true)}';

    return ValueListenableBuilder<VoicePlayback>(
      valueListenable: VoicePlayer.instance.playback,
      builder: (context, playback, _) {
        final isCurrent = playback.url == url;
        final isPlaying = isCurrent && playback.isPlaying;
        final loading = isCurrent && playback.isLoading;
        final shown = isCurrent && playback.duration > Duration.zero
            ? playback.duration - playback.position
            : recorded;

        return ListTile(
          onTap: () => VoicePlayer.instance.toggle(url).catchError((_) {}),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.secondary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      isPlaying ? AppIcons.pause : AppIcons.play,
                      size: 18,
                      color: Colors.white,
                    ),
            ),
          ),
          title: Text(
            (message['senderName'] as String?) ?? 'Member',
            style: context.textTheme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          subtitle: Text(
            when,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          trailing: Text(
            _duration(shown.isNegative ? Duration.zero : shown),
            style: TextStyle(
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}
