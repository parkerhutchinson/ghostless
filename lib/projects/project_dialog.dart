import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:file_selector/file_selector.dart';

import 'project.dart';
import 'project_logo.dart';
import '../app_theme.dart';
import '../tasks/form_buttons.dart';
import '../widgets/selected_text.dart';

/// What the project dialog returns: the name, color and logo (null for
/// none), or [delete].
typedef ProjectDialogResult = ({
  String name,
  int colorIndex,
  ProjectLogo? logo,
  bool delete,
});

/// Asks for a project's name, color and logo. Pass [project] to edit it, and
/// [canDelete] to offer Delete (the result's `delete` is then true).
/// Returns null when cancelled.
Future<ProjectDialogResult?> showProjectDialog(
  BuildContext context, {
  Project? project,
  int defaultColorIndex = 0,
  bool canDelete = false,
}) => showDialog(
  context: context,
  // The same dimmed backdrop as Settings.
  barrierColor: Colors.black54,
  builder: (_) => _ProjectDialog(
    project: project,
    defaultColorIndex: defaultColorIndex,
    canDelete: canDelete,
  ),
);

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({
    this.project,
    required this.defaultColorIndex,
    required this.canDelete,
  });
  final Project? project;
  final int defaultColorIndex;
  final bool canDelete;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final _name = AppTextController(text: widget.project?.name)
    ..addListener(() => setState(() {}));
  late int _color = widget.project?.colorIndex ?? widget.defaultColorIndex;
  late ProjectLogo? _logo = widget.project?.logo;

  /// Why the last picked logo was turned down.
  String? _logoError;

  Future<void> _pickLogo() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Logos',
          extensions: logoExtensions,
          uniformTypeIdentifiers: ['public.image', 'public.svg-image'],
        ),
      ],
    );
    if (file == null) return;
    try {
      final logo = await readLogo(await file.readAsBytes(), file.name);
      setState(() {
        _logo = logo;
        _logoError = null;
      });
    } on LogoException catch (e) {
      setState(() => _logoError = e.message);
    }
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (
      name: _name.text.trim(),
      colorIndex: _color,
      logo: _logo,
      delete: false,
    ));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Color [i] as a square to pick; outlined when it's the one picked.
  Widget _swatch(int i) => Semantics(
    label: 'Color ${i + 1}',
    selected: i == _color,
    child: InkWell(
      onTap: () => setState(() => _color = i),
      customBorder: formShape,
      child: Container(
        decoration: BoxDecoration(
          color: projectColors[i],
          borderRadius: formRadius,
          border: i == _color
              ? Border.all(color: context.colors.text, width: 2.5)
              : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isNew = widget.project == null;
    return AlertDialog(
      backgroundColor: context.colors.surface,
      title: Text(isNew ? 'New project' : 'Edit project'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            // The project's mark (its color, with its logo), then its
            // name; under them, why a picked logo was turned down.
            // The mark and the field, both [_markSize] tall.
            // Lined up at the top: the mark's box runs past its bottom
            // (see [_mark]); the gap after it is 14 to the mark itself.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 14 - _overhang,
              children: [
                _mark(),
                Expanded(
                  // At least the mark's height; a long name wraps and the
                  // field grows downward with it.
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    minLines: 1,
                    maxLines: null,
                    textAlignVertical: TextAlignVertical.center,
                    // Enter saves (a multi-line field would add a line).
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
                    ],
                    // One line (fixed at 21) plus its padding is exactly
                    // the mark's height. (A minimum height wouldn't do:
                    // the border is drawn around the text, not the box.)
                    style: const TextStyle(fontSize: 14),
                    strutStyle: const StrutStyle(
                      fontSize: 14,
                      height: _lineHeight / 14,
                      forceStrutHeight: true,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Project name',
                      // Not the desktop's compact density, which would
                      // take 8 off the height.
                      visualDensity: VisualDensity.standard,
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: (_markSize - _lineHeight) / 2,
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
            if (_logoError case final error?)
              Text(
                error,
                style: TextStyle(fontSize: 12, color: Colors.red.shade300),
              ),
            // Nine to a row, around the color wheel, across the full width
            // (each square, sized to fit).
            Column(
              spacing: 6,
              children: [
                for (
                  var start = 0;
                  start < projectColorOrder.length;
                  start += 9
                )
                  Row(
                    spacing: 6,
                    children: [
                      for (var k = start; k < start + 9; k++)
                        Expanded(
                          child: k < projectColorOrder.length
                              ? AspectRatio(
                                  aspectRatio: 1,
                                  child: _swatch(projectColorOrder[k]),
                                )
                              : const SizedBox(),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      // One row, so Delete sits at the left, apart from Cancel and Save.
      actions: [
        Row(
          spacing: 8,
          children: [
            if (widget.canDelete)
              FilledButton(
                style: deleteButtonStyle(),
                onPressed: () => Navigator.pop(context, (
                  name: _name.text.trim(),
                  colorIndex: _color,
                  logo: _logo,
                  delete: true,
                )),
                child: const Text('Delete project'),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _valid ? _submit : null,
              child: Text(isNew ? 'Create project' : 'Save'),
            ),
          ],
        ),
      ],
    );
  }

  /// The mark's size, and the name field's height beside it.
  static const _markSize = 36.0;

  /// How far the logo button hangs past the mark's bottom-right corner.
  static const _overhang = 8.0;

  /// The name field's line height: with its padding, one line is
  /// [_markSize] tall.
  static const _lineHeight = 21.0;

  static const _logoHint = 'Square: PNG, JPG, GIF, WebP or SVG';

  /// The project's color square (with its logo on it), and a small button
  /// on its corner to upload a logo; with one, it offers Replace and
  /// Remove.
  ///
  /// The box takes in the button where it hangs past the mark's corner
  /// ([_overhang]): clicks only land inside a widget's box, so a button
  /// hanging outside it would only answer on the part over the mark.
  Widget _mark() => SizedBox.square(
    dimension: _markSize + _overhang,
    child: Stack(
      children: [
        ProjectIcon.of(
          color: projectColors[_color % projectColors.length],
          logo: _logo,
          size: _markSize,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: _logo == null
              ? _markButton(
                  tooltip: 'Upload logo\n$_logoHint',
                  onPressed: _pickLogo,
                )
              : MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: const Icon(Symbols.upload, size: 18),
                      onPressed: _pickLogo,
                      child: const Text('Replace logo…'),
                    ),
                    MenuItemButton(
                      // No icon; in line with Replace logo's text.
                      leadingIcon: const SizedBox(width: 18),
                      onPressed: () => setState(() {
                        _logo = null;
                        _logoError = null;
                      }),
                      child: const Text('Remove logo'),
                    ),
                  ],
                  builder: (context, menu, _) => _markButton(
                    tooltip: 'Logo',
                    onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  ),
                ),
        ),
      ],
    ),
  );

  /// The upload button on the mark's corner: small, on the dialog's color
  /// with an outline, so it stands off the mark.
  Widget _markButton({
    required String tooltip,
    required VoidCallback onPressed,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: formRadius,
        side: BorderSide(color: context.colors.formBorder),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: formShape,
        child: SizedBox.square(
          dimension: 22,
          child: Icon(Symbols.upload, size: 14, color: context.colors.text),
        ),
      ),
    ),
  );
}
