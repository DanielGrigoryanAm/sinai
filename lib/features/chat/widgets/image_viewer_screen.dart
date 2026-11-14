import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// Full-screen picture with pinch-to-zoom and a button to save it to the
/// device gallery.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _saving = false;

  Future<void> _saveToGallery() async {
    if (_saving) return;
    setState(() => _saving = true);

    String message;
    try {
      if (!await Gal.hasPermission() && !await Gal.requestPermission()) {
        message = 'Allow access to photos to save pictures';
      } else {
        final bytes = await FirebaseStorage.instance
            .refFromURL(widget.imageUrl)
            .getData(20 * 1024 * 1024);
        if (bytes == null) throw StateError('Empty download');

        await Gal.putImageBytes(bytes);
        message = 'Saved to gallery';
      }
    } on GalException catch (e) {
      message = switch (e.type) {
        GalExceptionType.permissionDenied =>
          'Allow access to photos to save pictures',
        GalExceptionType.notEnoughSpace => 'Not enough storage space',
        _ => 'Could not save the photo',
      };
    } catch (_) {
      message = 'Could not save the photo';
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Save to gallery',
              icon: const Icon(Icons.download_rounded),
              onPressed: _saveToGallery,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
      ),
    );
  }
}
