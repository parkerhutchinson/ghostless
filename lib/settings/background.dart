import 'package:material_ui/material_ui.dart';

import '../layout.dart';

/// What's drawn behind the whole window.
sealed class Background {
  const Background();

  Map<String, Object?> toJson();

  /// The color the app's surfaces and borders are worked out from (see
  /// AppColors): a chosen color, or the default gray behind an image.
  Color get baseColor => switch (this) {
    ColorBackground(:final color) => color,
    _ => surfaceColor,
  };

  /// What the app starts with: about 80% black.
  static const initial = ColorBackground(surfaceColor);

  /// Unknown or broken values fall back to [initial].
  factory Background.fromJson(Map<String, Object?>? json) => switch (json) {
    {'type': 'color', 'color': final int argb} => ColorBackground(
      _darkened[argb] ?? Color(argb),
    ),
    {'type': 'image', 'file': final String file} when file.isNotEmpty =>
      ImageBackground(file),
    // 'default' was the mountains' name when they were the default.
    {'type': 'mountains' || 'default'} => const MountainsBackground(),
    _ => initial,
  };
}

/// The mountain image that ships with the app (an option in Settings).
final class MountainsBackground extends Background {
  const MountainsBackground();

  static const asset = 'assets/background.png';

  @override
  Map<String, Object?> toJson() => {'type': 'mountains'};

  @override
  bool operator ==(Object other) => other is MountainsBackground;
  @override
  int get hashCode => 0;
}

/// An image the user picked, copied into the app's backgrounds folder.
final class ImageBackground extends Background {
  const ImageBackground(this.fileName);
  final String fileName;

  @override
  Map<String, Object?> toJson() => {'type': 'image', 'file': fileName};

  @override
  bool operator ==(Object other) =>
      other is ImageBackground && other.fileName == fileName;
  @override
  int get hashCode => fileName.hashCode;
}

/// A solid color.
final class ColorBackground extends Background {
  const ColorBackground(this.color);
  final Color color;

  @override
  Map<String, Object?> toJson() => {'type': 'color', 'color': color.toARGB32()};

  @override
  bool operator ==(Object other) =>
      other is ColorBackground && other.color.toARGB32() == color.toARGB32();
  @override
  int get hashCode => color.toARGB32();
}

/// The colors offered in Settings: dark, so the app's white text reads
/// well and the surfaces and borders worked out from them stay subtle.
const backgroundColors = [
  surfaceColor, // about 80% black (the default)
  Color(0xFF0C386A), // blue
  Color(0xFF072759), // navy
  Color(0xFF003A33), // teal
  Color(0xFF19451C), // green
  Color(0xFF261558), // indigo
  Color(0xFF3A0F55), // purple
  Color(0xFF5F0B30), // magenta
  Color(0xFF6D1616), // red
  Color(0xFF77250C), // orange
  Color(0xFF33231E), // brown
  Color(0xFF1E272B), // slate
  Color(0xFF121212), // black
];

/// The brighter colors Settings used to offer, each mapped to its darker
/// replacement in [backgroundColors], so a saved choice stays selected.
const _darkened = {
  0xFF1565C0: Color(0xFF0C386A),
  0xFF0D47A1: Color(0xFF072759),
  0xFF00695C: Color(0xFF003A33),
  0xFF2E7D32: Color(0xFF19451C),
  0xFF4527A0: Color(0xFF261558),
  0xFF6A1B9A: Color(0xFF3A0F55),
  0xFFAD1457: Color(0xFF5F0B30),
  0xFFC62828: Color(0xFF6D1616),
  0xFFD84315: Color(0xFF77250C),
  0xFF5D4037: Color(0xFF33231E),
  0xFF37474F: Color(0xFF1E272B),
};
