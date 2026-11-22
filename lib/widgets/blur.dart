import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Blurs RGBA pixels ([width] × [height], 4 bytes each) in place: three
/// box blurs of [radius] each way, which together come out close to a
/// Gaussian. Edges repeat their last pixel.
void boxBlurRgba(Uint8List pixels, int width, int height, int radius) {
  if (radius < 1 || width == 0 || height == 0) return;
  final scratch = Uint8List(pixels.length);
  for (var pass = 0; pass < 3; pass++) {
    _blurLines(pixels, scratch, width, height, radius, horizontal: true);
    _blurLines(scratch, pixels, width, height, radius, horizontal: false);
  }
}

/// One box blur along every row (or column) of [src] into [dst].
void _blurLines(
  Uint8List src,
  Uint8List dst,
  int width,
  int height,
  int radius, {
  required bool horizontal,
}) {
  final lines = horizontal ? height : width;
  final length = horizontal ? width : height;
  // Byte distance between neighbours along a line, and between lines.
  final step = horizontal ? 4 : width * 4;
  final lineStep = horizontal ? width * 4 : 4;
  final span = radius * 2 + 1;
  for (var line = 0; line < lines; line++) {
    final base = line * lineStep;
    int at(int i) => base + i.clamp(0, length - 1) * step;
    for (var c = 0; c < 4; c++) {
      var sum = 0;
      for (var i = -radius; i <= radius; i++) {
        sum += src[at(i) + c];
      }
      for (var i = 0; i < length; i++) {
        dst[base + i * step + c] = sum ~/ span;
        sum += src[at(i + radius + 1) + c] - src[at(i - radius) + c];
      }
    }
  }
}

/// Width the background is decoded at before blurring: small enough to
/// blur quickly, large enough to stay smooth when drawn full window.
const _blurWidth = 320;

/// Blur radius at [_blurWidth] (three passes): strong, like frosted glass.
const _blurRadius = 4;

final _cache = <ImageProvider, Future<ui.Image?>>{};

/// [image] decoded small and blurred (once per image, off the UI thread);
/// null if it can't be read.
Future<ui.Image?> blurredImage(ImageProvider image) {
  if (_cache.length > 4) _cache.remove(_cache.keys.first);
  return _cache[image] ??= _blur(image);
}

Future<ui.Image?> _blur(ImageProvider provider) async {
  try {
    final small = await _resolve(
      ResizeImage(provider, width: _blurWidth, policy: ResizeImagePolicy.fit),
    );
    final w = small.width, h = small.height;
    final data = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    if (data == null) return null;
    final pixels = await compute(_blurTask, (data.buffer.asUint8List(), w, h));
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return await done.future;
  } catch (_) {
    return null;
  }
}

/// The decoded image (a copy the caller owns).
Future<ui.Image> _resolve(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (e, s) {
      done.completeError(e, s);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future;
}

Uint8List _blurTask((Uint8List, int, int) job) {
  final (pixels, w, h) = job;
  boxBlurRgba(pixels, w, h, _blurRadius);
  return pixels;
}
