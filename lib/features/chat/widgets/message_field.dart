import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

class MessageField extends StatefulWidget {
  const MessageField({
    super.key,
    required this.chatController,
    required this.chatCode,
    this.onMessageSent,
  });

  final TextEditingController chatController;
  final String chatCode;
  final VoidCallback? onMessageSent;

  @override
  State<MessageField> createState() => _MessageFieldState();
}

class _MessageFieldState extends State<MessageField> {
  /// Photo the user picked but has not sent yet.
  Uint8List? _pendingImage;
  String _pendingImageType = 'image/jpeg';

  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _recordingTime = Stopwatch();
  Timer? _recordingTicker;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // The mic turns into the send button as soon as there is text.
    widget.chatController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.chatController.removeListener(_onTextChanged);
    _recordingTicker?.cancel();
    if (_isRecording) _recorder.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  Future<void> _startRecording() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (!await _recorder.hasPermission()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Allow microphone access to record voice messages'),
          ),
        );
        return;
      }

      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        // Mono speech at a modest bitrate keeps voice messages small.
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
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
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not start recording')),
      );
    }
  }

  void _stopRecordingTimer() {
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
        ),
      );
      widget.onMessageSent?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save the recording')),
      );
    }
  }

  /// Sends the attached photo, if any, followed by the typed text.
  void _send() {
    final text = widget.chatController.text.trim();
    final image = _pendingImage;
    if (text.isEmpty && image == null) return;

    final bloc = context.read<ChatBloc>();

    if (image != null) {
      bloc.add(
        SendImageEvent(
          chatCode: widget.chatCode,
          bytes: image,
          contentType: _pendingImageType,
        ),
      );
      setState(() => _pendingImage = null);
    }

    if (text.isNotEmpty) {
      bloc.add(SendMessageEvent(chatCode: widget.chatCode, text: text));
      widget.chatController.clear();
    }

    widget.onMessageSent?.call();
  }

  /// Lets the user pick a photo from the gallery or take one. The photo is
  /// only attached; it is sent with the send button.
  Future<void> _attachImage() async {
    final messenger = ScaffoldMessenger.of(context);

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
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      // Downscaled and re-encoded by the picker, so uploads stay small.
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingImage = bytes;
        _pendingImageType = picked.mimeType ?? 'image/jpeg';
      });
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the photo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final pendingImage = _pendingImage;
    final canSend =
        pendingImage != null || widget.chatController.text.trim().isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pendingImage != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: _PendingImagePreview(
              bytes: pendingImage,
              onRemove: () => setState(() => _pendingImage = null),
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
                  textInputAction: TextInputAction.send,
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
                    hintText: 'Message...',
                    hintStyle: context.textTheme.hintText.copyWith(
                      fontSize: 16,
                    ),
                    prefixIcon: Padding(
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
            icon: Icon(Icons.delete_outline, color: colors.textSecondary),
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
                    Icons.close,
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
