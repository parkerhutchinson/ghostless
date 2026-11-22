import 'package:material_ui/material_ui.dart';

import '../layout.dart';

/// The image drawn behind the whole window, over the background color.
/// It's only a picture: the app's colors come from the background color
/// (see [backgroundColorFromJson]), whichever image is showing.
sealed class Background {
  const Background();

  Map<String, Object?> toJson();

  /// No image (also for unknown or broken values, and for the old
  /// `{'type': 'color'}`, when the color and image were one setting).
  static Background? fromJson(Map<String, Object?>? json) => switch (json) {
    {'type': 'image', 'file': final String file} when file.isNotEmpty =>
      ImageBackground(file),
    // 'mountains' was the image that came with the app before this one.
    {'type': 'default' || 'mountains'} => const DefaultBackground(),
    _ => null,
  };
}

/// What the app starts with: about 80% black.
const initialBackgroundColor = surfaceColor;

/// The background color saved in [settings] (a profile's theme): it sets
/// the app's surfaces, borders and text. Older settings kept it in
/// `background` (as `{'type': 'color'}`) before an image could sit over it.
Color backgroundColorFromJson(Map<String, Object?> settings) =>
    switch ((settings['backgroundColor'], settings['background'])) {
      (final int argb, _) || (_, {'type': 'color', 'color': final int argb}) =>
        _darkened[argb] ?? Color(argb),
      _ => initialBackgroundColor,
    };

/// The image that ships with the app: what a new profile starts with.
final class DefaultBackground extends Background {
  const DefaultBackground();

  static const asset = 'assets/default-background.jpg';

  @override
  Map<String, Object?> toJson() => {'type': 'default'};

  @override
  bool operator ==(Object other) => other is DefaultBackground;
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

/// The colors offered in Settings: the default, then a dark version of
/// each accent color (27% of it, toward black), around the color wheel
/// like the accents; near-black and off-white; then a light version of
/// each accent. Dark, so the app's white text reads well and the
/// surfaces and borders worked out from them stay subtle.
const backgroundColors = [
  surfaceColor, // about 80% black (the default)
  Color(0xFF3D181A), // red
  Color(0xFF3E2119), // orange
  Color(0xFF3E2815), // amber
  Color(0xFF3D3012), // yellow
  Color(0xFF2A3413), // lime
  Color(0xFF193015), // leaf green
  Color(0xFF153024), // green
  Color(0xFF14312D), // aqua
  Color(0xFF153036), // teal
  Color(0xFF192E3C), // sky
  Color(0xFF192641), // blue
  Color(0xFF211F3C), // indigo
  Color(0xFF31223B), // purple
  Color(0xFF3A2038), // magenta
  Color(0xFF3C1D2B), // pink
  Color(0xFF262A2F), // gray
  Color(0xFF0E0E0E), // near-black
  // Light: the app's text and icons turn dark on it (see AppColors).
  Color(0xFFF2F1ED), // off-white
  // A light version of each accent (70% of the way to white), in the
  // same order. The app's text and icons turn dark on these too.
  Color(0xFFF6CECF), // light red
  Color(0xFFF8D6CE), // light orange
  Color(0xFFF8E0C9), // light amber
  Color(0xFFF6E8C6), // light yellow
  Color(0xFFE1EDC8), // light lime
  Color(0xFFCFE8C9), // light leaf green
  Color(0xFFCAE8DB), // light green
  Color(0xFFC9E8E4), // light aqua
  Color(0xFFCAE8EE), // light teal
  Color(0xFFCEE6F6), // light sky
  Color(0xFFCEDCFA), // light blue
  Color(0xFFD8D5F4), // light indigo
  Color(0xFFE8D8F4), // light purple
  Color(0xFFF3D5F0), // light magenta
  Color(0xFFF6D4E2), // light pink
  Color(0xFFDCE1E7), // light gray
];

/// The brighter colors Settings offered long ago, each mapped to the dark
/// one that replaced it (no longer in [backgroundColors]: kept as a
/// custom color).
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

/// The background image showing behind the window (null: none, just the
/// color), drawn to cover it. Frosted glass draws it again, blurred (see
/// FrostedBar). Provided above the navigator; null when absent (tests).
class BackgroundImageScope extends InheritedWidget {
  const BackgroundImageScope({
    super.key,
    required this.image,
    required super.child,
  });

  final ImageProvider? image;

  static ImageProvider? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackgroundImageScope>()?.image;

  @override
  bool updateShouldNotify(BackgroundImageScope old) => old.image != image;
}
