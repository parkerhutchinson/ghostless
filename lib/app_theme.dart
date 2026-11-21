import 'package:material_ui/material_ui.dart';

import 'layout.dart';

/// Corner radius of every button, chip and input in the app: the task
/// form's style. No pill-shaped buttons anywhere.
const formRadius = BorderRadius.all(Radius.circular(4));
const formShape = RoundedRectangleBorder(borderRadius: formRadius);

/// Corner radius of a whole board column being dragged (its feedback and
/// the drop highlight). A touch rounder than [formRadius] because at 4px a
/// box that big looks too sharp. Cards and everything else stay at 4px.
const containerRadius = BorderRadius.all(Radius.circular(6));
const containerShape = RoundedRectangleBorder(borderRadius: containerRadius);

/// The default accent (a dark blue): filled buttons, the selected
/// Board/List toggle, the + button, the selected project, selected chips
/// and highlighted text. Changeable in Settings (see [accentColors]); in
/// widgets, read it from the theme: `Theme.of(context).colorScheme.primary`.
const defaultAccent = Color(0xFF21245C);

/// The accent colors offered in Settings, the default first. All dark
/// enough for white text on top.
const accentColors = [
  defaultAccent,
  Color(0xFF1565C0), // blue
  Color(0xFF00695C), // teal
  Color(0xFF2E7D32), // green
  Color(0xFF4527A0), // indigo
  Color(0xFF6A1B9A), // purple
  Color(0xFFAD1457), // magenta
  Color(0xFFC62828), // red
  Color(0xFFD84315), // orange
  Color(0xFF5D4037), // brown
  Color(0xFF455A64), // slate
];

/// Whether [color] is light enough to need dark text on it.
bool isLightColor(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.light;

/// Text and icons drawn on a [fill] (an accent, a swatch): white on dark
/// colors, near-black on light ones.
Color contrastOn(Color fill) =>
    isLightColor(fill) ? const Color(0xFF1C1C1C) : Colors.white;

/// Every surface, border, hover shade and text color in the app, worked
/// out from one base color: the background color picked in Settings (the
/// default gray for an image background). Read it with `context.colors`.
///
/// Darker sections (column panels, dividers) mix in black. Borders and
/// hover fills mix in the text color: white on a dark base, black on a
/// light one, so they always show and stay in the base color's hue. Text
/// turns dark on a light base.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors._({
    required this.isLight,
    required this.text,
    required this.mutedText,
    required this.placeholder,
    required this.surface,
    required this.card,
    required this.column,
    required this.divider,
    required this.cardBorder,
    required this.formBorder,
    required this.hover,
    required this.rowHover,
    required this.hoverStrong,
    required this.dropHighlight,
    required this.emptySlot,
  });

  factory AppColors.from(Color base) {
    final isLight = isLightColor(base);
    final text = isLight ? const Color(0xFF1C1C1C) : Colors.white;
    Color dark(double t) => Color.lerp(base, Colors.black, t)!;
    // Toward the text color: lighter on a dark base, darker on a light one.
    Color edge(double t) => Color.lerp(base, text, t)!;
    return AppColors._(
      isLight: isLight,
      text: text,
      mutedText: isLight ? const Color(0xFF5E5E5E) : const Color(0xFFBDBDBD),
      placeholder: text.withValues(alpha: 0.3),
      surface: base,
      // A touch lighter than the background (darker on a light one), so
      // cards and list rows stand off it.
      card: edge(isLight ? 0.035 : 0.05),
      // Black shows far more on a light base, so less of it.
      column: dark(isLight ? 0.07 : 0.22),
      divider: dark(isLight ? 0.14 : 0.31),
      cardBorder: edge(0.12),
      formBorder: edge(0.18),
      hover: edge(0.09),
      // Over a row's [card] fill, a step further.
      rowHover: edge(isLight ? 0.08 : 0.1),
      hoverStrong: edge(0.15),
      dropHighlight: edge(0.19),
      emptySlot: dark(isLight ? 0.06 : 0.15),
    );
  }

  /// The base is light (e.g. a white background): text is dark.
  final bool isLight;

  /// Titles and body text: white, or near-black on a light base.
  final Color text;

  /// Secondary text and icons: labels, dates, ⋯ and + icons.
  final Color mutedText;

  /// Empty fields' hint text.
  final Color placeholder;

  /// Text on a tag chip tinted with the tag's [color]: a lighter shade of
  /// it on a dark base, a darker one on a light base.
  Color chipText(Color color) => isLight
      ? Color.lerp(color, Colors.black, 0.4)!
      : Color.lerp(color, Colors.white, 0.45)!;

  /// The sidebar, cards, the task form, dialogs and menus.
  final Color surface;

  /// Behind each board column's cards: darker, so the cards stand out.
  final Color column;

  /// Hard lines between surfaces.
  final Color divider;

  /// Outlines of cards, labels and swatches.
  final Color cardBorder;

  /// Outlines of form fields, and the sidebar's and task form's edges.
  final Color formBorder;

  /// Behind an icon button while hovered; the ⋯ tiles.
  final Color hover;

  /// A list view row while hovered: subtler than [hover].
  final Color rowHover;

  /// A ⋯ tile while hovered.
  final Color hoverStrong;

  /// A sidebar project while a task is dragged over it.
  final Color dropHighlight;

  /// The slot a dragged card leaves behind.
  final Color emptySlot;

  /// Task cards and list rows: slightly lighter than [surface] on a dark
  /// background, slightly darker on a light one.
  final Color card;

  /// The outline of the form's text fields and dropdowns.
  OutlineInputBorder get fieldBorder => OutlineInputBorder(
    borderRadius: formRadius,
    borderSide: BorderSide(color: formBorder),
  );

  /// The ⋯ menu buttons (task cards, sidebar projects): a square-cornered
  /// tile instead of a round hover splash.
  ButtonStyle get menuButtonStyle => ButtonStyle(
    shape: const WidgetStatePropertyAll(formShape),
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.hovered) ? hoverStrong : hover,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    fixedSize: const WidgetStatePropertyAll(Size(26, 26)),
    minimumSize: const WidgetStatePropertyAll(Size(26, 26)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors._(
      isLight: t < 0.5 ? isLight : other.isLight,
      text: l(text, other.text),
      mutedText: l(mutedText, other.mutedText),
      placeholder: l(placeholder, other.placeholder),
      surface: l(surface, other.surface),
      card: l(card, other.card),
      column: l(column, other.column),
      divider: l(divider, other.divider),
      cardBorder: l(cardBorder, other.cardBorder),
      formBorder: l(formBorder, other.formBorder),
      hover: l(hover, other.hover),
      rowHover: l(rowHover, other.rowHover),
      hoverStrong: l(hoverStrong, other.hoverStrong),
      dropHighlight: l(dropHighlight, other.dropHighlight),
      emptySlot: l(emptySlot, other.emptySlot),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The app's surface and border colors (see [AppColors]).
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.from(surfaceColor);
}

/// The app's theme: [accent] for highlights, and surfaces and borders from
/// [base] (see [AppColors]). Button, chip, input and toggle shapes come from
/// here, so new controls get the form style automatically.
ThemeData buildAppTheme({
  Color accent = defaultAccent,
  Color base = surfaceColor,
}) {
  final colors = AppColors.from(base);
  final onAccent = contrastOn(accent);
  final brightness = colors.isLight ? Brightness.light : Brightness.dark;
  final theme = ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: base,
    extensions: [colors],
    colorScheme: ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
        .copyWith(
          primary: accent,
          onPrimary: onAccent,
          primaryContainer: accent,
          onPrimaryContainer: onAccent,
          // The selected segment of a SegmentedButton.
          secondaryContainer: accent,
          onSecondaryContainer: onAccent,
          surface: base,
          onSurface: colors.text,
          outline: colors.formBorder,
          outlineVariant: colors.cardBorder,
        ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: accent,
      cursorColor: colors.text,
      selectionHandleColor: accent,
    ),
  );
  const shape = WidgetStatePropertyAll<OutlinedBorder>(formShape);
  const style = ButtonStyle(shape: shape);
  return theme.copyWith(
    // Text buttons have no fill, so the dark accent would be unreadable as
    // their text; they use the text color.
    textButtonTheme: TextButtonThemeData(
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(colors.text),
      ),
    ),
    filledButtonTheme: const FilledButtonThemeData(style: style),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: style),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: style),
    segmentedButtonTheme: const SegmentedButtonThemeData(style: style),
    // Icon-only buttons too: a square hover/press highlight, not a circle.
    // Every icon is the text color (white, or dark on a light background),
    // like the Board/List toggle's.
    // Material Symbols at a lighter weight than the default 400: thinner
    // strokes. Use `Symbols.*` icons (not `Icons.*`, a fixed-weight font).
    iconTheme: theme.iconTheme.copyWith(color: colors.text, weight: 300),
    // Menu items' icons (Rename, Delete…).
    listTileTheme: theme.listTileTheme.copyWith(iconColor: colors.text),
    iconButtonTheme: IconButtonThemeData(
      style: style.copyWith(
        foregroundColor: WidgetStatePropertyAll(colors.text),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.pressed)
              ? colors.hover
              : null,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: formShape,
      // Flat: no shadow in any state.
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      disabledElevation: 0,
      backgroundColor: accent,
      foregroundColor: onAccent,
    ),
    // Every scrollbar's thumb is the accent.
    scrollbarTheme: theme.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(accent),
    ),
    // Long tooltips (a full task title) wrap onto more lines instead of
    // stretching across the window.
    tooltipTheme: theme.tooltipTheme.copyWith(
      constraints: const BoxConstraints(maxWidth: 320),
    ),
    chipTheme: theme.chipTheme.copyWith(shape: formShape),
    dialogTheme: theme.dialogTheme.copyWith(
      shape: formShape,
      backgroundColor: base,
    ),
    datePickerTheme: theme.datePickerTheme.copyWith(shape: formShape),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      shape: formShape,
      color: base,
    ),
    // Toasts (the undo bar): the accent with white text and action
    // (dark on a light accent).
    snackBarTheme: theme.snackBarTheme.copyWith(
      shape: formShape,
      backgroundColor: accent,
      contentTextStyle: TextStyle(color: onAccent),
      actionTextColor: onAccent,
      closeIconColor: onAccent,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: formRadius),
    ),
  );
}
