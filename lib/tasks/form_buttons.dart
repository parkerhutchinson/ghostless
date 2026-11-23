import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'label_colors.dart';

/// Text size of the task form's chips (labels, projects).
const formChipFontSize = 12.5;

/// Height of the task form's chips, and of its buttons.
const formChipHeight = 32.0;

/// The task form's buttons (Mark complete, Save changes, the labels'
/// Save): the size of its chips (their height and text size).
final formButtonStyle = FilledButton.styleFrom(
  textStyle: const TextStyle(
    fontSize: formChipFontSize,
    fontWeight: FontWeight.w400,
  ),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  minimumSize: const Size(0, formChipHeight),
  fixedSize: const Size.fromHeight(formChipHeight),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.standard,
);

/// The red of delete buttons: the first accent preset around the color
/// wheel (Settings).
Color get deleteColor => labelPalette[labelPickerOrder.first];

/// A delete button (Delete project, Delete column, Delete and save): a red
/// outline and red text, filled red (with dark text) only while hovered
/// or pressed. For a [FilledButton]; merge it onto a size style.
ButtonStyle deleteButtonStyle() {
  final red = deleteColor;
  bool active(Set<WidgetState> s) =>
      s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => active(s) ? red : Colors.transparent,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => active(s) ? accentText : red,
    ),
    // The fill is the hover: it switches at once (no eased fade of the
    // fill and text), with no overlay or ripple on top of it.
    animationDuration: Duration.zero,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
    side: WidgetStatePropertyAll(BorderSide(color: red)),
  );
}

/// The ← that closes a form without saving: a square the height of
/// [formButtonStyle]'s buttons.
class FormCloseButton extends StatelessWidget {
  const FormCloseButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Close',
    onPressed: onPressed,
    iconSize: 18,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(
      width: formChipHeight,
      height: formChipHeight,
    ),
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    icon: Icon(Symbols.arrow_back),
  );
}
