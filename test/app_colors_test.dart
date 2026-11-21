import 'package:codename/app_theme.dart';
import 'package:codename/layout.dart';
import 'package:codename/settings/background.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  double lum(Color c) => c.computeLuminance();

  test('the default gray gives the original shades', () {
    final c = AppColors.from(surfaceColor);
    expect(c.surface, surfaceColor);
    // Cards stand off the background: a touch lighter on a dark one.
    expect(lum(c.card), greaterThan(lum(surfaceColor)));
    // Close to the old fixed values (#232323, #1F1F1F, #474747, #404040).
    expect(c.column.toARGB32(), closeTo(0xFF232323, 0x020202));
    expect(c.divider.toARGB32(), closeTo(0xFF1F1F1F, 0x020202));
    expect(c.cardBorder.toARGB32(), closeTo(0xFF474747, 0x020202));
    expect(c.hover.toARGB32(), closeTo(0xFF404040, 0x020202));
  });

  test('darker sections are darker and borders lighter than the base', () {
    const base = Color(0xFF00695C);
    final c = AppColors.from(base);
    for (final darker in [c.column, c.divider, c.emptySlot]) {
      expect(lum(darker), lessThan(lum(base)));
    }
    for (final lighter in [
      c.cardBorder,
      c.formBorder,
      c.hover,
      c.hoverStrong,
      c.dropHighlight,
    ]) {
      expect(lum(lighter), greaterThan(lum(base)));
    }
  });

  test('shades keep the base color\'s hue', () {
    const base = Color(0xFF6A1B9A); // purple
    final c = AppColors.from(base);
    final hue = HSLColor.fromColor(base).hue;
    for (final shade in [c.column, c.formBorder, c.hover]) {
      expect(HSLColor.fromColor(shade).hue, closeTo(hue, 1));
    }
  });

  test('a color background is the base; an image falls back to gray', () {
    const teal = Color(0xFF00695C);
    expect(const ColorBackground(teal).baseColor, teal);
    expect(const MountainsBackground().baseColor, surfaceColor);
    expect(const ImageBackground('x.png').baseColor, surfaceColor);
  });

  test('the theme carries the palette and uses the base for surfaces', () {
    const teal = Color(0xFF00695C);
    final theme = buildAppTheme(base: teal);
    expect(theme.extension<AppColors>()!.surface, teal);
    expect(theme.scaffoldBackgroundColor, teal);
    expect(theme.dialogTheme.backgroundColor, teal);
  });

  test('a light base turns text dark and borders darker than it', () {
    final c = AppColors.from(Colors.white);
    expect(lum(c.card), lessThan(1));
    expect(c.isLight, isTrue);
    expect(isLightColor(c.text), isFalse);
    expect(isLightColor(c.mutedText), isFalse);
    expect(c.cardBorder.computeLuminance(), lessThan(1));
    expect(buildAppTheme(base: Colors.white).brightness, Brightness.light);
  });

  test('a dark base keeps white text', () {
    final c = AppColors.from(surfaceColor);
    expect(c.isLight, isFalse);
    expect(c.text, Colors.white);
    expect(buildAppTheme().brightness, Brightness.dark);
  });

  test('text on an accent contrasts with it', () {
    expect(contrastOn(defaultAccent), Colors.white);
    expect(isLightColor(contrastOn(const Color(0xFFFFEB3B))), isFalse);
    expect(
      buildAppTheme(accent: const Color(0xFFFFEB3B)).colorScheme.onPrimary,
      contrastOn(const Color(0xFFFFEB3B)),
    );
  });
}
