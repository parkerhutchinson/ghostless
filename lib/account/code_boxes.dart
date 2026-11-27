import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';

/// A sign-in code typed into a row of boxes, one digit each.
///
/// It's one hidden text field under the boxes, so typing moves along the
/// boxes, backspace steps back, and pasting a whole code (even "123 456"
/// or "123-456") fills every box at once.
class CodeBoxes extends StatelessWidget {
  const CodeBoxes({
    super.key,
    required this.controller,
    required this.focus,
    required this.length,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int length;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  /// The gap between boxes, as a share of a box's width.
  static const _gapRatio = 0.2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    // Square boxes across the whole width (the boxes aren't a one-line
    // field, so they're not held to formFieldHeight).
    return AspectRatio(
      aspectRatio: (length + (length - 1) * _gapRatio) / 1,
      child: Stack(
        children: [
          // The field that takes the typing: there, but not seen.
          Positioned.fill(
            child: TextSelectionTheme(
              data: const TextSelectionThemeData(
                selectionColor: Colors.transparent,
              ),
              child: TextField(
                controller: controller,
                focusNode: focus,
                enabled: enabled,
                keyboardType: TextInputType.number,
                autocorrect: false,
                enableSuggestions: false,
                showCursor: false,
                style: const TextStyle(color: Colors.transparent),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(length),
                ],
                decoration: const InputDecoration.collapsed(hintText: null),
                onChanged: onChanged,
                onSubmitted: (_) => onSubmitted(),
              ),
            ),
          ),
          // The boxes, drawn over it (clicks go through to the field).
          Positioned.fill(
            child: IgnorePointer(
              child: ListenableBuilder(
                listenable: Listenable.merge([controller, focus]),
                builder: (context, _) => LayoutBuilder(
                  builder: (context, constraints) {
                    final text = controller.text;
                    final next = text.length.clamp(0, length - 1);
                    return Row(
                      spacing: _gapRatio * constraints.maxHeight,
                      children: [
                        for (var i = 0; i < length; i++)
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: formRadius,
                                border: focus.hasFocus && i == next
                                    ? Border.all(color: accent, width: 2)
                                    : Border.all(color: colors.formBorder),
                              ),
                              child: Center(
                                child: Text(
                                  i < text.length ? text[i] : '',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: enabled
                                        ? colors.text
                                        : colors.mutedText,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
