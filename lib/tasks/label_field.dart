import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../widgets/picker_dropdown.dart';
import 'form_buttons.dart' show formChipFontSize;
import 'label_colors.dart';
import 'project_labels.dart' show clipLabel, maxLabelLength;
import 'task_card.dart' show LabelChip;

/// One choice under the label field: an existing [label], or (when
/// [isNew]) what's typed, to create.
typedef LabelOption = ({String label, bool isNew});

/// The choices for [query]: first what's typed, to create (unless it's
/// already a label, ignoring case), then the [known] labels containing it
/// that aren't [chosen] yet. With nothing typed, all of them.
List<LabelOption> labelOptions(
  String query, {
  required List<String> known,
  required List<String> chosen,
}) {
  final q = query.trim().toLowerCase();
  final taken = {for (final l in chosen) l.toLowerCase()};
  final matches = [
    for (final l in known)
      if (!taken.contains(l.toLowerCase()) && l.toLowerCase().contains(q))
        (label: l, isNew: false),
  ];
  final exists = taken.contains(q) || known.any((l) => l.toLowerCase() == q);
  return [
    if (q.isNotEmpty && !exists) (label: query.trim(), isNew: true),
    // An exact match first, then the rest as they are (sorted).
    ...matches.where((m) => m.label.toLowerCase() == q),
    ...matches.where((m) => m.label.toLowerCase() != q),
  ];
}

/// The task form's way to add labels, a [PickerDropdown]: [builder] makes
/// the labels' row, with what opens the box (the + after the labels, or
/// "Add label"). The box lists [options] for what's typed: with nothing
/// typed, every label not on the task yet. Enter adds what's typed; ↑ ↓
/// then Enter, or a click, adds a listed one. A new label gets the color
/// picked in the swatches under "Create". The list is worked out afresh on
/// every build, so it's never stale after adding a label.
class LabelField extends StatefulWidget {
  const LabelField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.projectId,
    required this.options,
    required this.onAdd,
    required this.builder,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The task's origin: the project whose label colors the list shows.
  final String projectId;
  final List<LabelOption> Function(String text) options;

  /// Adds a label (or comma-separated labels), clearing the field; a new
  /// one in [color] (a [labelPalette] index) when given.
  final void Function(String text, {int? color}) onAdd;

  /// The row the box opens under; its toggle opens (and, clicked again,
  /// closes) the box.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  State<LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<LabelField> {
  /// The color picked for a new label; null for its default.
  int? _newColor;

  int get _createColor =>
      _newColor ?? defaultLabelColor(widget.controller.text.trim());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (widget.controller.text.trim().isEmpty && _newColor != null) {
      setState(() => _newColor = null);
    }
  }

  /// Adds [text]; when it's a new label, in the picked color.
  void _add(String text, {bool isNew = false}) {
    final color = isNew ? _createColor : null;
    setState(() => _newColor = null);
    widget.onAdd(text, color: color);
  }

  void _pick(LabelOption o) => _add(o.label, isNew: o.isNew);

  @override
  Widget build(BuildContext context) => PickerDropdown(
    controller: widget.controller,
    focusNode: widget.focusNode,
    hint: 'Find or create label',
    inputFormatters: const [LabelLengthFormatter()],
    count: (text) => widget.options(text).length,
    list: (context, text, highlight) {
      final options = widget.options(text);
      if (options.isEmpty) return null;
      return _LabelList(
        options: options,
        highlight: highlight,
        onPick: _pick,
        projectId: widget.projectId,
        createColor: _createColor,
        onColor: (c) => setState(() => _newColor = c),
      );
    },
    onSubmitted: (text, highlight) {
      final options = widget.options(text);
      if (highlight != null) {
        _pick(options[highlight]);
      } else if (text.trim().isNotEmpty) {
        _add(text, isNew: options.firstOrNull?.isNew ?? false);
      }
    },
    onChanged: (v) {
      if (v.contains(',')) _add(v);
    },
    builder: widget.builder,
  );
}

/// The labels in the box, under its field: each label as its chip, the
/// [highlight]ed one (↑ ↓) shaded.
class _LabelList extends StatelessWidget {
  const _LabelList({
    required this.options,
    required this.highlight,
    required this.onPick,
    required this.projectId,
    required this.createColor,
    required this.onColor,
  });
  final List<LabelOption> options;
  final int? highlight;
  final ValueChanged<LabelOption> onPick;
  final String projectId;

  /// The color a new label is created in, and picking another.
  final int createColor;
  final ValueChanged<int> onColor;

  @override
  Widget build(BuildContext context) => PickerList(
    itemCount: options.length,
    itemBuilder: (context, i) {
      final option = options[i];
      final item = PickerItem(
        active: i == highlight,
        onTap: () => onPick(option),
        child: option.isNew
            ? Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Icon(Symbols.add, size: 14, color: context.colors.mutedText),
                  const Text('Create', style: TextStyle(fontSize: 13)),
                  Flexible(
                    child: LabelChip(
                      option.label,
                      projectId: projectId,
                      color: labelPalette[createColor],
                      fontSize: formChipFontSize,
                    ),
                  ),
                ],
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: LabelChip(
                  option.label,
                  projectId: projectId,
                  fontSize: formChipFontSize,
                ),
              ),
      );
      if (!option.isNew) return item;
      // The new label's color, under "Create".
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          item,
          _Swatches(selected: createColor, onSelected: onColor),
          if (i < options.length - 1)
            Divider(height: 9, color: context.colors.cardBorder),
        ],
      );
    },
  );
}

/// The label colors as small squares; [selected] outlined.
class _Swatches extends StatelessWidget {
  const _Swatches({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 2, 8, 6),
    // Eight to a row.
    child: SizedBox(
      width: 8 * 18 + 7 * 6,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          // Around the color wheel, red to pink, then gray.
          for (final (i, color) in [
            for (final i in labelPickerOrder) (i, labelPalette[i]),
          ])
            // Named for screen readers; no tooltip (one can't be placed
            // inside this list, which follows the field).
            Semantics(
              label: 'Label color ${i + 1}',
              button: true,
              child: InkWell(
                onTap: () => onSelected(i),
                customBorder: formShape,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: formRadius,
                    border: i == selected
                        ? Border.all(color: context.colors.text, width: 2)
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Keeps each label typed in a field (several, separated by commas) to
/// [maxLabelLength] characters: typing past it does nothing; a paste is
/// cut short.
class LabelLengthFormatter extends TextInputFormatter {
  const LabelLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final parts = newValue.text.split(',');
    bool tooLong(String p) => p.trim().characters.length > maxLabelLength;
    if (!parts.any(tooLong)) return newValue;
    // Typed one more: refused, as if the field were full.
    if (!oldValue.text.split(',').any(tooLong) &&
        newValue.text.length == oldValue.text.length + 1) {
      return oldValue;
    }
    final text = [
      for (final p in parts)
        if (tooLong(p))
          p.substring(0, p.length - p.trimLeft().length) + clipLabel(p)
        else
          p,
    ].join(',');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: newValue.selection.end.clamp(0, text.length),
      ),
    );
  }
}
