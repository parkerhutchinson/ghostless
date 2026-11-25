import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The longest side an added image keeps, in pixels: sharp in the
/// full-window viewer, a fraction of a camera photo's size.
const maxImageSide = 2048;

/// JPEG quality for added images: no visible loss at this size.
const imageJpegQuality = 82;

/// An image (or any file) as stored: its bytes and extension (no dot).
typedef StoredFile = ({List<int> bytes, String extension});

/// Makes an added image smaller, off the main thread: scaled down to
/// [maxSide] on its longest side, and saved as JPEG (quality [quality]),
/// or as PNG if it has see-through parts. Returns the original as is when
/// it isn't an image this can redo (a PDF, HEIC, an animated GIF, a
/// broken file), or when redoing it wouldn't make it smaller.
Future<StoredFile> compressImage(
  List<int> bytes,
  String extension, {
  int maxSide = maxImageSide,
  int quality = imageJpegQuality,
}) => Isolate.run(
  () => compressImageNow(bytes, extension, maxSide: maxSide, quality: quality),
);

/// [compressImage]'s work, on the calling thread (for tests, and inside
/// the isolate).
StoredFile compressImageNow(
  List<int> bytes,
  String extension, {
  int maxSide = maxImageSide,
  int quality = imageJpegQuality,
}) {
  final original = (bytes: bytes, extension: extension);
  final ext = extension.toLowerCase();
  if (!_redoable.contains(ext)) return original;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
    );
  } catch (_) {
    return original;
  }
  if (decoded == null) return original;
  // Animated (a GIF, an animated WebP): left alone, or it would stop.
  if (decoded.numFrames > 1) return original;

  // A photo's rotation (in its EXIF data, which isn't kept) turned into
  // its pixels, so it stays upright.
  var image = img.bakeOrientation(decoded);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxSide,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxSide,
            interpolation: img.Interpolation.average,
          );
  }
  final StoredFile redone = _hasTransparency(image)
      ? (bytes: img.encodePng(image, level: 6), extension: 'png')
      : (bytes: img.encodeJpg(image, quality: quality), extension: 'jpg');
  return redone.bytes.length < bytes.length ? redone : original;
}

/// Formats this can read and write again. Not HEIC (it can't read it),
/// nor PDF and other documents.
const _redoable = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tiff'};

/// Whether any pixel is at all see-through (only images with an alpha
/// channel can be).
bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  final max = image.maxChannelValue;
  for (final p in image) {
    if (p.a < max) return true;
  }
  return false;
}

/// [name] with [storedFile]'s extension, when the stored file's type
/// changed (a PNG photo saved as JPEG: "photo.png" becomes "photo.jpg").
/// "jpeg" and "jpg" count as the same.
String withExtensionOf(String name, String storedFile) {
  String extOf(String s) {
    final dot = s.lastIndexOf('.');
    return dot == -1 ? '' : s.substring(dot + 1).toLowerCase();
  }

  String normal(String e) => e == 'jpeg' ? 'jpg' : e;
  final stored = extOf(storedFile);
  if (stored.isEmpty || normal(extOf(name)) == normal(stored)) return name;
  final dot = name.lastIndexOf('.');
  return '${dot == -1 ? name : name.substring(0, dot)}.$stored';
}
