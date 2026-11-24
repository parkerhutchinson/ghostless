import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'form_buttons.dart';
import 'label_colors.dart';
import 'label_field.dart' show LabelLengthFormatter;
import 'project_labels.dart';

/// One label as edited in [LabelsSheet], applied only on Save.
class _Draft {
  _Draft(this.original, this.color) : name = original, originalColor = color;

  final String original;
  final int originalColor;
  String name;
  int color;
  bool deleted = false;

  bool get renamed => name.trim().isNotEmpty && name.trim() != original;
  bool get recolored => color != originalColor;
  bool get changed => deleted || renamed || recolored;
}

/// Edits a project's labels, in a card over the task form: each one's
/// color, name and Delete. Nothing changes until Save, which applies it
/// all (to the project and its tasks) and notes it in [changes], so the
/// form can follow. The ←, Escape or a click beside the card close it,
/// dropping the edits; [onClose] either way.
class LabelsSheet extends StatefulWidget {
  const LabelsSheet({
    super.key,
    required this.labels,
    required this.changes,
    required this.projectName,
    required this.onClose,
  });
  final ProjectLabels labels;
  final LabelChanges changes;
  final String projectName;
  final VoidCallback onClose;

  @override
  State<LabelsSheet> createState() => _LabelsSheetState();
}

class _LabelsSheetState extends State<LabelsSheet> {
  late final List<_Draft> _drafts = [
    for (final l in widget.labels.all()) _Draft(l, widget.labels.colorOf(l)),
  ];

  /// Save was pressed with deletions that take labels off tasks: asking
  /// first.
  bool _confirming = false;

  bool get _dirty => _drafts.any((d) => d.changed);

  List<_Draft> get _deleted => [
    for (final d in _drafts)
      if (d.deleted) d,
  ];

  /// Tasks that lose a label when the deletions are saved.
  int get _tasksLosingLabels =>
      _deleted.fold(0, (sum, d) => sum + widget.labels.usage(d.original));

  void _save() {
    if (!_dirty) return;
    if (!_confirming && _tasksLosingLabels > 0) {
      setState(() => _confirming = true);
      return;
    }
    final labels = widget.labels, changes = widget.changes;
    for (final d in _drafts.where((d) => d.deleted)) {
      labels.delete(d.original, changes);
    }
    for (final d in _drafts.where((d) => !d.deleted)) {
      if (d.renamed) labels.rename(d.original, d.name, changes);
      if (d.recolored) {
        labels.setColor(d.renamed ? d.name.trim() : d.original, d.color);
      }
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    return Actions(
      // Escape closes this card, not the whole form.
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            if (_confirming) {
              setState(() => _confirming = false);
            } else {
              widget.onClose();
            }
            return null;
          },
        ),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // A click beside the card closes it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(
                  color: context.colors.surface.withValues(alpha: 0.6),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Material(
                  color: context.colors.surface,
                  elevation: 8,
                  shadowColor: Colors.black,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: formRadius,
                    side: BorderSide(color: context.colors.formBorder),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _confirming ? _confirm() : _list(),
                          ),
                        ),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _title(String text) => Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  );

  Widget _list() {
    final shown = [
      for (final d in _drafts)
        if (!d.deleted) d,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        _title('Labels in ${widget.projectName}'),
        if (shown.isEmpty)
          Text('No labels.', style: TextStyle(color: context.colors.mutedText))
        else
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  for (final d in shown)
                    _LabelRow(
                      key: ObjectKey(d),
                      draft: d,
                      usage: widget.labels.usage(d.original),
                      onChanged: () => setState(() {}),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _confirm() {
    final deleted = _deleted;
    final count = _tasksLosingLabels;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        _title(
          deleted.length == 1
              ? 'Delete "${deleted.single.original}"?'
              : 'Delete ${deleted.length} labels?',
        ),
        Text(
          '${deleted.length == 1 ? 'It' : 'They'} will be removed from '
          '$count task${count == 1 ? '' : 's'}.',
        ),
      ],
    );
  }

  /// Like the task form's: a line above, ← on the left, Save on the right.
  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.colors.formBorder)),
    ),
    child: Row(
      children: [
        FormCloseButton(
          onPressed: _confirming
              ? () => setState(() => _confirming = false)
              : widget.onClose,
        ),
        const Spacer(),
        FilledButton(
          style: _confirming
              ? deleteButtonStyle().merge(formButtonStyle)
              : formButtonStyle,
          onPressed: _dirty ? _save : null,
          child: Text(_confirming ? 'Delete and save' : 'Save'),
        ),
      ],
    ),
  );
}

/// One label: its color (click to change), its name, how many tasks have
/// it, and Delete. Edits go into [draft].
class _LabelRow extends StatefulWidget {
  const _LabelRow({
    super.key,
    required this.draft,
    required this.usage,
    required this.onChanged,
  });
  final _Draft draft;
  final int usage;
  final VoidCallback onChanged;

  @override
  State<_LabelRow> createState() => _LabelRowState();
}

class _LabelRowState extends State<_LabelRow> {
  late final _name = TextEditingController(text: widget.draft.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final color = labelPalette[draft.color];
    // The color and the name are one control: the swatch (rounded on
    // the left) and the field (rounded on the right) share a border line.
    const height = 32.0;
    const left = BorderRadius.horizontal(left: Radius.circular(4));
    const right = OutlineInputBorder(
      borderRadius: BorderRadius.horizontal(right: Radius.circular(4)),
    );
    final line = BorderSide(color: context.colors.formBorder);
    return Row(
      children: [
        // The colors in a grid, in a menu sized exactly to it.
        MenuAnchor(
          style: MenuStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(Size.zero),
            backgroundColor: WidgetStatePropertyAll(context.colors.surface),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: formRadius,
                side: BorderSide(color: context.colors.formBorder),
              ),
            ),
          ),
          menuChildren: [
            _SwatchGrid(
              selected: draft.color,
              onPicked: (c) {
                draft.color = c;
                widget.onChanged();
              },
            ),
          ],
          builder: (context, menu, _) => Tooltip(
            message: 'Color',
            child: InkWell(
              onTap: () => menu.isOpen ? menu.close() : menu.open(),
              customBorder: const RoundedRectangleBorder(borderRadius: left),
              child: Container(
                width: height,
                height: height,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: left,
                  border: Border.fromBorderSide(line),
                ),
              ),
            ),
          ),
        ),
        // Over the swatch's right edge by its 1px border, so the two
        // share one line.
        Expanded(
          child: Transform.translate(
            offset: const Offset(-1, 0),
            // Exactly the swatch's height: the field fills it, the text
            // centered (one line: line breaks aren't allowed).
            child: SizedBox(
              height: height,
              child: TextField(
                controller: _name,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.center,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                  const LabelLengthFormatter(),
                ],
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  hintText: draft.original,
                  hintStyle: TextStyle(color: context.colors.placeholder),
                  border: right,
                  enabledBorder: right.copyWith(borderSide: line),
                  focusedBorder: right.copyWith(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (v) {
                  draft.name = v;
                  widget.onChanged();
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Delete label',
          iconSize: 18,
          onPressed: () {
            draft.deleted = true;
            widget.onChanged();
          },
          icon: Icon(Symbols.close, size: 16, color: context.colors.mutedText),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, this.size = 16, this.selected = false});
  final Color color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: formRadius,
      border: selected
          ? Border.all(color: context.colors.text, width: 2)
          : null,
    ),
  );
}

/// The label colors as a grid of squares, eight across, with [_inset]
/// on every side; a click picks one (its index) and closes the menu.
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({required this.selected, required this.onPicked});
  final int selected;
  final ValueChanged<int> onPicked;

  // Two rows of eight, around the color wheel.
  static const _size = 28.0, _gap = 6.0, _columns = 8;

  /// Space around the grid, on every side.
  static const _inset = 18.0;

  Widget _swatch(BuildContext context, int i) => Semantics(
    label: 'Color ${i + 1}',
    button: true,
    selected: i == selected,
    child: InkWell(
      onTap: () {
        MenuController.maybeOf(context)?.close();
        onPicked(i);
      },
      customBorder: formShape,
      child: _Swatch(
        color: labelPalette[i],
        size: _size,
        selected: i == selected,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Around the color wheel, red to pink, then gray.
    final order = labelPickerOrder;
    final count = order.length;
    return Padding(
      padding: const EdgeInsets.all(_inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: _gap,
        children: [
          for (var row = 0; row * _columns < count; row++)
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: _gap,
              children: [
                for (
                  var i = row * _columns;
                  i < count && i < (row + 1) * _columns;
                  i++
                )
                  _swatch(context, order[i]),
              ],
            ),
        ],
      ),
    );
  }
}
