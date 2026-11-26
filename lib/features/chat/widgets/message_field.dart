import 'dart:async';
import 'dart:typed_data';
import 'package:sinai/common/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:sinai/common/toast.dart';
import 'package:sinai/features/chat/widgets/watch_together.dart';
import 'package:sinai/common/photo_compress.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/widgets/composer_controller.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

class MessageField extends StatefulWidget {
  const MessageField({
    super.key,
    required this.chatController,
    required this.chatCode,
    required this.composer,
    this.focusNode,
    this.onMessageSent,
  });

  final TextEditingController chatController;
  final String chatCode;

  /// Reply or edit in progress, set from the message menu.
  final ComposerController composer;
  final FocusNode? focusNode;
  final VoidCallback? onMessageSent;

  @override
  State<MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<MessageField> {
  /// Photos the user picked but has not sent yet.
  final List<({Uint8List bytes, String type})> _pendingImages = [];
  static const _maxImages = 10;

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _recordingTime = Stopwatch();
  Timer? _recordingTicker;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // The mic turns into the send button as soon as there is text.
    widget.chatController.addListener(_onTextChanged);
    widget.composer.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.chatController.removeListener(_onTextChanged);
    widget.composer.removeListener(_onTextChanged);
    _recordingTicker?.cancel();
    if (_isRecording) _recorder.cancel();
    videoHold.value = false;
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        showToast('Allow microphone access to record voice messages',
            kind: ToastKind.error);
        return;
      }

      // Videos pause so they don't talk over the recording.
      videoHold.value = true;
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        // Mono speech at 32 kbit/s: clear for voice, about 240 KB a minute.
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 24000,
          numChannels: 1,
        ),
        path: path,
      );

      if (!mounted) return;
      _recordingTime
        ..reset()
        ..start();
      _recordingTicker = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => setState(() {}),
      );
      setState(() => _isRecording = true);
    } catch (_) {
      videoHold.value = false;
      showToast('Could not start recording', kind: ToastKind.error);
    }
  }

  void _stopRecordingTimer() {
    videoHold.value = false;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    _recordingTime.stop();
  }

  Future<void> _cancelRecording() async {
    _stopRecordingTimer();
    setState(() => _isRecording = false);
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  Future<void> _sendRecording() async {
    final bloc = context.read<ChatBloc>();
    final duration = _recordingTime.elapsed;
    _stopRecordingTimer();
    setState(() => _isRecording = false);

    try {
      // An accidental tap is not a message.
      if (duration < const Duration(milliseconds: 700)) {
        await _recorder.cancel();
        return;
      }

      final path = await _recorder.stop();
      if (path == null) return;

      bloc.add(
        SendVoiceEvent(
          chatCode: widget.chatCode,
          filePath: path,
          duration: duration,
          replyTo: _takeReply(),
        ),
      );
      widget.onMessageSent?.call();
    } catch (_) {
      if (!mounted) return;
      showToast('Could not save the recording', kind: ToastKind.error);
    }
  }

  /// The reply being composed, as stored on the sent message. Clears it,
  /// since a reply goes with the next message only.
  ReplyPreview? _takeReply() {
    final replyTo = widget.composer.replyTo;
    widget.composer.clear();
    return replyTo == null ? null : ReplyPreview.of(replyTo);
  }

  /// Saves an edit, or sends the attached photo, if any, followed by the
  /// typed text.
  void _send() {
    final text = widget.chatController.text.trim();
    final bloc = context.read<ChatBloc>();

    final editing = widget.composer.editing;
    if (editing != null) {
      if (text.isEmpty) return;
      if (text != editing.text) {
        bloc.add(
          EditMessageEvent(
            chatCode: widget.chatCode,
            messageId: editing.id,
            text: text,
          ),
        );
      }
      widget.chatController.clear();
      widget.composer.clear();
      return;
    }

    final images = List.of(_pendingImages);
    if (text.isEmpty && images.isEmpty) return;

    final reply = _takeReply();

    if (images.isNotEmpty) {
      for (var i = 0; i < images.length; i++) {
        final isLast = i == images.length - 1;
        bloc.add(
          SendImageEvent(
            chatCode: widget.chatCode,
            bytes: images[i].bytes,
            contentType: images[i].type,
            replyTo: i == 0 ? reply : null,
            // The typed text becomes the caption of the last photo.
            caption: isLast ? text : '',
          ),
        );
      }
      setState(_pendingImages.clear);
      widget.chatController.clear();
    } else if (text.isNotEmpty) {
      bloc.add(
        SendMessageEvent(
          chatCode: widget.chatCode,
          text: text,
          replyTo: reply,
        ),
      );
      widget.chatController.clear();
    }

    widget.onMessageSent?.call();
  }

  void _cancelEdit() {
    widget.composer.clear();
    widget.chatController.clear();
  }

  /// Lets the user pick a photo from the gallery or take one. The photo is
  /// only attached; it is sent with the send button.
  Future<void> _attachImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.colorTheme.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(AppIcons.addImage),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(AppIcons.camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    final room = _maxImages - _pendingImages.length;
    if (room <= 0) {
      showToast('Up to 10 photos at a time');
      return;
    }

    try {
      // Downscaled and re-encoded by the picker, so uploads stay small.
      final picker = ImagePicker();
      final List<XFile> picked = source == ImageSource.gallery
          ? await picker.pickMultiImage(
              maxWidth: 1600,
              maxHeight: 1600,
              imageQuality: 80,
              limit: room > 1 ? room : null,
            )
          : [
              if (await picker.pickImage(
                source: source,
                maxWidth: 1600,
                maxHeight: 1600,
                imageQuality: 80,
              )
                  case final XFile file)
                file,
            ];
      if (picked.isEmpty) return;

      final added = <({Uint8List bytes, String type})>[];
      for (final file in picked.take(room)) {
        // Re-encoded small: PNGs and screenshots stay large otherwise.
        added.add(await compressPhoto(
          await file.readAsBytes(),
          file.mimeType ?? 'image/jpeg',
        ));
      }
      if (!mounted) return;
      setState(() => _pendingImages.addAll(added));
    } catch (_) {
      showToast('Could not open the photo', kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final replyTo = widget.composer.replyTo;
    final editing = widget.composer.editing;
    final canSend = editing != null ||
        _pendingImages.isNotEmpty ||
        widget.chatController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (replyTo != null)
          _ComposerBar(
            icon: AppIcons.reply,
            title: 'Reply to ${replyTo.senderName}',
            text: replyTo.previewText,
            onClose: widget.composer.clear,
          ),
        if (editing != null)
          _ComposerBar(
            icon: AppIcons.edit,
            title: 'Edit message',
            text: editing.text,
            onClose: _cancelEdit,
          ),
        if (_pendingImages.isNotEmpty && editing == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 8),
                itemCount: _pendingImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, index) => _PendingImagePreview(
                  bytes: _pendingImages[index].bytes,
                  onRemove: () =>
                      setState(() => _pendingImages.removeAt(index)),
                ),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: _isRecording
              ? _RecordingBar(
                  elapsed: _recordingTime.elapsed,
                  onCancel: _cancelRecording,
                  onSend: _sendRecording,
                )
              : TextField(
                  cursorColor: colors.secondary,
                  controller: widget.chatController,
                  focusNode: widget.focusNode,
                  textInputAction: TextInputAction.send,
                  // Long text wraps and the field grows, up to 6 lines;
                  // beyond that it scrolls inside.
                  minLines: 1,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  // Handling the action here instead of onSubmitted keeps the
                  // keyboard open, so several messages can be sent in a row.
                  onEditingComplete: _send,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colors.backgroundSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: BorderSide.none,
                    ),
                    hintText: _pendingImages.isNotEmpty && editing == null
                        ? 'Add a caption...'
                        : 'Message...',
                    hintStyle: context.textTheme.hintText.copyWith(
                      fontSize: 16,
                    ),
                    // An edit changes the text only.
                    prefixIcon: editing != null
                        ? null
                        : Padding(
                            padding: const EdgeInsets.only(left: 5),
                            child: IconButton(
                              tooltip: 'Attach photo',
                              icon: Assets.icons.photo.image(
                                height: 32,
                                width: 32,
                              ),
                              onPressed: _attachImage,
                            ),
                          ),
                    contentPadding: editing != null
                        ? const EdgeInsets.fromLTRB(20, 16, 12, 16)
                        : null,
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: canSend
                          ? IconButton(
                              tooltip: 'Send',
                              icon: Assets.icons.send.image(
                                height: 35,
                                width: 35,
                              ),
                              onPressed: _send,
                            )
                          : IconButton(
                              tooltip: 'Record voice message',
                              icon: Assets.icons.mic.image(
                                height: 34,
                                width: 34,
                              ),
                              onPressed: _startRecording,
                            ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Bar above the field showing the message being replied to or edited.
class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.icon,
    required this.title,
    required this.text,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final textTheme = context.textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.secondary, size: 22),
          const SizedBox(width: 10),
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.secondary,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: Icon(AppIcons.close, color: colors.textSecondary, size: 20),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Shown in place of the text field while a voice message is recording.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.onCancel,
    required this.onSend,
  });

  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final minutes = elapsed.inMinutes;
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 5),
          IconButton(
            tooltip: 'Cancel recording',
            icon: Icon(AppIcons.trash, color: colors.textSecondary),
            onPressed: onCancel,
          ),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Color(0xFFDC2626),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$minutes:$seconds',
            style: context.textTheme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Recording…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyLarge.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Send voice message',
            icon: Assets.icons.send.image(height: 35, width: 35),
            onPressed: onSend,
          ),
          const SizedBox(width: 5),
        ],
      ),
    );
  }
}

/// Thumbnail of the attached photo with a remove button on its corner.
class _PendingImagePreview extends StatelessWidget {
  const _PendingImagePreview({required this.bytes, required this.onRemove});

  final Uint8List bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Extra room so the remove button can overhang the thumbnail.
      width: 84,
      height: 84,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Material(
              color: const Color(0xFF1B2030),
              shape: const CircleBorder(
                side: BorderSide(color: Colors.white, width: 2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    AppIcons.close,
                    size: 14,
                    color: Colors.white,
                    semanticLabel: 'Remove photo',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
