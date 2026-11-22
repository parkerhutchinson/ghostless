import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import 'project.dart';

/// Largest logo, in pixels each way. Logos are stored in the project
/// itself (so they sync), which keeps them small.
const maxLogoSize = 256;

/// Largest logo file, in bytes.
const maxLogoBytes = 256 * 1024;

/// File types a logo can be.
const logoExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'];

/// A project's (company's) logo: a small square image, or an SVG.
final class ProjectLogo {
  const ProjectLogo({required this.bytes, required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;

  Map<String, Object?> toJson() => {
    'format': isSvg ? 'svg' : 'image',
    'data': base64Encode(bytes),
  };

  /// Null when [json] isn't a logo. The same data gives the same object,
  /// so a logo isn't decoded (and redrawn) again on every change.
  static ProjectLogo? fromJson(Object? json) {
    if (json case {'format': final String format, 'data': final String data}) {
      final key = '$format:$data';
      if (_decoded[key] case final logo?) return logo;
      try {
        final logo = ProjectLogo(
          bytes: base64Decode(data),
          isSvg: format == 'svg',
        );
        if (_decoded.length > 50) _decoded.remove(_decoded.keys.first);
        return _decoded[key] = logo;
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  static final _decoded = <String, ProjectLogo>{};
}

/// Why a picked logo can't be used.
final class LogoException implements Exception {
  const LogoException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Null when an image [width] × [height] can be a logo; otherwise why not.
String? checkLogoSize(num width, num height) {
  if (width <= 0 || height <= 0) return "Couldn't read the image's size.";
  if (width != height) {
    return 'The logo must be square (this one is '
        '${_px(width)} × ${_px(height)}).';
  }
  if (width > maxLogoSize) {
    return 'The logo can be at most $maxLogoSize × $maxLogoSize '
        '(this one is ${_px(width)} × ${_px(height)}).';
  }
  return null;
}

String _px(num n) => n == n.roundToDouble() ? '${n.round()}' : '$n';

/// An SVG's width and height: from its viewBox, else its width and height
/// attributes. Null when it has neither.
(double, double)? svgSize(String svg) {
  final tag = RegExp(r'<svg\b[^>]*>', caseSensitive: false).firstMatch(svg);
  if (tag == null) return null;
  String? attr(String name) => RegExp(
    '\\b$name\\s*=\\s*["\']([^"\']*)["\']',
    caseSensitive: false,
  ).firstMatch(tag[0]!)?[1];

  if (attr('viewBox') case final box?) {
    final parts = box
        .trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (parts.length == 4 && parts.every((p) => p != null)) {
      return (parts[2]!, parts[3]!);
    }
  }
  double? length(String? value) =>
      value == null ? null : double.tryParse(value.trim().replaceAll('px', ''));
  final w = length(attr('width')), h = length(attr('height'));
  return w == null || h == null ? null : (w, h);
}

/// Checks [bytes] (from a file named [fileName]) as a logo: square, at most
/// [maxLogoSize] each way (an SVG only needs to be square, as it scales).
/// Throws a [LogoException] saying what's wrong.
Future<ProjectLogo> readLogo(Uint8List bytes, String fileName) async {
  if (bytes.length > maxLogoBytes) {
    throw LogoException(
      'The logo file is too big (at most ${maxLogoBytes ~/ 1024} KB).',
    );
  }
  if (fileName.toLowerCase().endsWith('.svg')) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const LogoException("That SVG couldn't be read.");
    }
    final size = svgSize(text);
    if (size == null) {
      throw const LogoException(
        'The SVG needs a viewBox (or a width and height) to check it\'s '
        'square.',
      );
    }
    if (size.$1 != size.$2 || size.$1 <= 0) {
      throw LogoException(checkLogoSize(size.$1, size.$2)!);
    }
    return ProjectLogo(bytes: bytes, isSvg: true);
  }

  final int width, height;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    width = frame.image.width;
    height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
  } catch (_) {
    throw const LogoException("That image couldn't be read.");
  }
  if (checkLogoSize(width, height) case final problem?) {
    throw LogoException(problem);
  }
  return ProjectLogo(bytes: bytes, isSvg: false);
}

/// A project's mark: a rounded square in its color, [size] each way, with
/// its logo on it when it has one.
class ProjectIcon extends StatelessWidget {
  ProjectIcon({super.key, required Project project, this.size = 18})
    : color = project.color,
      logo = project.logo;

  const ProjectIcon.of({
    super.key,
    required this.color,
    this.logo,
    this.size = 18,
  });

  final Color color;
  final ProjectLogo? logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logo = this.logo;
    final side = size;
    // A black or white square on a background of the same shade gets an
    // outline, so it still shows.
    final faint =
        (color.computeLuminance() - context.colors.surface.computeLuminance())
            .abs() <
        0.08;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: color,
        borderRadius: formRadius,
        border: faint
            ? Border.all(color: context.colors.mutedText, width: 0.5)
            : null,
      ),
      padding: logo == null ? null : EdgeInsets.all(side * 0.12),
      child: logo == null ? null : LogoImage(logo: logo, size: side),
    );
  }
}

/// [logo] fitted into [size] × [size].
class LogoImage extends StatelessWidget {
  const LogoImage({super.key, required this.logo, required this.size});
  final ProjectLogo logo;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: logo.isSvg
        ? SvgPicture.memory(logo.bytes, fit: BoxFit.contain)
        : Image.memory(
            logo.bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
          ),
  );
}
