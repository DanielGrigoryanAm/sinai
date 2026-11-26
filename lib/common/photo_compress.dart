import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Shrinks a photo before it is sent: at most [maxSide] pixels on the long
/// side, re-encoded as JPEG. Screenshots and PNGs, which the picker leaves
/// large, come out as small as camera photos. On a phone screen the
/// difference doesn't show; in storage and on mobile data it does.
///
/// Falls back to the original bytes if the photo can't be re-encoded.
Future<({Uint8List bytes, String type})> compressPhoto(
  Uint8List bytes,
  String type, {
  int maxSide = 1600,
  int quality = 75,
}) async {
  try {
    final out = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: maxSide,
      minHeight: maxSide,
      quality: quality,
      format: CompressFormat.jpeg,
      // Keeps photos the right way up.
      autoCorrectionAngle: true,
      keepExif: false,
    );
    // Already small JPEGs can come out larger; keep whichever is smaller.
    if (out.isEmpty || (out.length >= bytes.length && type == 'image/jpeg')) {
      return (bytes: bytes, type: type);
    }
    return (bytes: out, type: 'image/jpeg');
  } catch (e) {
    debugPrint('Compressing the photo failed, sending it as is: $e');
    return (bytes: bytes, type: type);
  }
}
