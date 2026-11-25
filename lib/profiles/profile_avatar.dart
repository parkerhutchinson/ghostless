import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../projects/project.dart' show projectColors, projectHueCount;
import 'profile.dart';
import '../files/arriving_file.dart';

/// A profile's round picture: their photo, else their initials on a color
/// of their own, else a person icon. Circular by design (like the color
/// dots), so it's not a 4px square.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.image,
    this.size = 26,
  });

  final Profile profile;

  /// The photo's file, when it has one.
  final File? image;
  final double size;

  /// A steady color per profile, from the project palette.
  Color get _color =>
      projectColors[profile.id.hashCode.abs() % projectHueCount];

  @override
  Widget build(BuildContext context) {
    final initials = profile.initials;
    final fallback = initials.isEmpty
        ? Icon(Symbols.person, size: size * 0.62, color: context.colors.text)
        : Text(
            initials,
            style: TextStyle(
              fontSize: size * 0.4,
              fontWeight: FontWeight.w400,
              color: Colors.white,
              height: 1,
            ),
          );
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: initials.isEmpty ? context.colors.hover : _color,
      ),
      // The outline is drawn over the photo, not around it: a border in
      // the decoration insets the child, leaving a ring the photo doesn't
      // fill.
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.formBorder),
      ),
      alignment: Alignment.center,
      child: image == null
          ? fallback
          : ArrivingFile(
              file: image!,
              builder: (context) => Image.file(
                image!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                // Missing file (deleted outside the app): initials instead.
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
