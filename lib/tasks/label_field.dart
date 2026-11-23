import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'label_colors.dart';
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

/// The task form's label field. While it's focused, a list under it shows
/// [options] for what's typed: with nothing typed, every label not on the
/// task yet. Enter adds what's typed (like before there was a list); ↑ ↓
/// then Enter, or a click, adds a listed one. A new label gets the color
/// picked in the swatches under "Create". The list is worked out
/// afresh on every build, so it's never stale after adding a label.
class LabelField extends StatefulWidget {
  const LabelField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.projectId,
    required this.options,
    required this.onAdd,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The task's origin: the project whose label colors the list shows.
  final String projectId;
  final List<LabelOption> Function(String text) options;

  /// Adds a label (or comma-separated labels), clearing the field; a new
  /// one in [color] (a [labelPalette] index) when given.
  final void Function(String text, {int? color}) onAdd;

  @override
  State<LabelField> createState() => _LabelFieldState();
}

class _LabelFieldState extends State<LabelField> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// The listed option ↑ ↓ moved to; null until they're used (Enter then
  /// adds what's typed).
  int? _highlight;

  /// Escape closed the list; it opens again on typing or refocusing.
  bool _dismissed = false;

  String _lastText = '';

  /// The color picked for a new label; null for its default.
  int? _newColor;

  int get _createColor =>
      _newColor ?? defaultLabelColor(widget.controller.text.trim());

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
    widget.controller.addListener(_onText);
    if (widget.focusNode.hasFocus) _portal.show();
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onFocus() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    setState(() {
      _dismissed = false;
      _highlight = null;
    });
    if (focused && !_portal.isShowing) {
      _portal.show();
    } else if (!focused && _portal.isShowing) {
      _portal.hide();
    }
  }

  void _onText() {
    if (widget.controller.text == _lastText) return;
    _lastText = widget.controller.text;
    setState(() {
      _dismissed = false;
      _highlight = null;
      if (widget.controller.text.trim().isEmpty) _newColor = null;
    });
  }

  /// Adds [text]; when it's a new label, in the picked color.
  void _add(String text, {bool isNew = false}) {
    final color = isNew ? _createColor : null;
    setState(() {
      _highlight = null;
      _newColor = null;
    });
    widget.onAdd(text, color: color);
  }

  void _pick(LabelOption o) => _add(o.label, isNew: o.isNew);

  KeyEventResult _onKey(FocusNode node, KeyEvent event, int count) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (count == 0 || _dismissed) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlight = ((_highlight ?? -1) + 1) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() => _highlight = ((_highlight ?? count) - 1) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Closes the list only; the next Escape closes the form.
        setState(() => _dismissed = true);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options(widget.controller.text);
    final highlight = _highlight != null && _highlight! < options.length
        ? _highlight
        : null;
    final showList = !_dismissed && options.isNotEmpty;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => !showList
            ? const SizedBox.shrink()
            : CompositedTransformFollower(
                link: _link,
                targetAnchor: Alignment.bottomLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  // Clicks in the list keep the field focused.
                  child: TextFieldTapRegion(
                    child: _LabelList(
                      options: options,
                      highlight: highlight,
                      onPick: _pick,
                      projectId: widget.projectId,
                      createColor: _createColor,
                      onColor: (c) => setState(() => _newColor = c),
                    ),
                  ),
                ),
              ),
        child: Focus(
          onKeyEvent: (node, event) => _onKey(node, event, options.length),
          child: SizedBox(
            width: 200,
            child: TextField(
              // Never scrolls (or bounces) on its own: a swipe over it
              // scrolls the form instead.
              scrollPhysics: const NeverScrollableScrollPhysics(),
              controller: widget.controller,
              focusNode: widget.focusNode,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Add label, press Enter',
                hintStyle: TextStyle(color: context.colors.placeholder),
                border: InputBorder.none,
              ),
              // Keeps focus after Enter, to add another.
              onEditingComplete: () {},
              onSubmitted: (text) {
                if (highlight != null && showList) {
                  _pick(options[highlight]);
                } else if (text.trim().isNotEmpty) {
                  _add(text, isNew: options.firstOrNull?.isNew ?? false);
                } else {
                  widget.focusNode.requestFocus();
                }
              },
              onChanged: (v) {
                if (v.contains(',')) _add(v);
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The list under the label field: each label as its chip, the
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
  Widget build(BuildContext context) => Material(
    color: context.colors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: formRadius,
      side: BorderSide(color: context.colors.cardBorder),
    ),
    elevation: 4,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: 240,
        minWidth: 200,
        maxWidth: 280,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        shrinkWrap: true,
        itemCount: options.length,
        itemBuilder: (context, i) {
          final option = options[i];
          final active = i == highlight;
          if (active) {
            // Keeps the highlighted one in view as ↑ ↓ move it.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                Scrollable.ensureVisible(context, alignment: 0.5);
              }
            });
          }
          final item = InkWell(
            borderRadius: formRadius,
            onTap: () => onPick(option),
            child: Container(
              decoration: BoxDecoration(
                color: active ? context.colors.hover : null,
                borderRadius: formRadius,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: option.isNew
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        Icon(
                          Symbols.add,
                          size: 14,
                          color: context.colors.mutedText,
                        ),
                        const Text('Create', style: TextStyle(fontSize: 13)),
                        Flexible(
                          child: LabelChip(
                            option.label,
                            projectId: projectId,
                            color: labelPalette[createColor],
                          ),
                        ),
                      ],
                    )
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: LabelChip(option.label, projectId: projectId),
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
              Divider(height: 9, color: context.colors.cardBorder),
            ],
          );
        },
      ),
    ),
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
