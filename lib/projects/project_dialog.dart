import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:file_selector/file_selector.dart';

import 'project.dart';
import 'project_logo.dart';
import '../app_theme.dart';

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
  // No scrim: the dialog sits directly on the app.
  barrierColor: Colors.transparent,
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
  late final _name = TextEditingController(text: widget.project?.name)
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
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Project name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            _logoRow(),
            // Nine to a row, around the color wheel.
            SizedBox(
              width: 9 * 26 + 8 * 6,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final i in projectColorOrder)
                    Semantics(
                      label: 'Color ${i + 1}',
                      selected: i == _color,
                      child: InkWell(
                        onTap: () => setState(() => _color = i),
                        customBorder: formShape,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: projectColors[i],
                            borderRadius: formRadius,
                            border: i == _color
                                ? Border.all(
                                    color: context.colors.text,
                                    width: 2.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade300,
                ),
                onPressed: () => Navigator.pop(context, (
                  name: _name.text.trim(),
                  colorIndex: _color,
                  logo: _logo,
                  delete: true,
                )),
                icon: const Icon(Symbols.delete, size: 18),
                label: const Text('Delete project'),
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

  /// The logo (or, without one, the color it falls back to), with
  /// buttons to choose or remove it.
  Widget _logoRow() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 8,
    children: [
      Row(
        spacing: 12,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: formRadius,
              border: Border.all(color: context.colors.cardBorder),
            ),
            alignment: Alignment.center,
            child: ProjectIcon.of(
              color: projectColors[_color % projectColors.length],
              logo: _logo,
              size: 40,
            ),
          ),
          OutlinedButton.icon(
            onPressed: _pickLogo,
            icon: const Icon(Symbols.upload, size: 18),
            label: Text(_logo == null ? 'Add logo…' : 'Replace logo…'),
          ),
          if (_logo != null)
            TextButton(
              onPressed: () => setState(() => _logo = null),
              child: const Text('Remove'),
            ),
        ],
      ),
      Text(
        _logoError ??
            'Square, up to $maxLogoSize × $maxLogoSize: PNG, JPG, GIF, WebP '
                'or SVG.',
        style: TextStyle(
          fontSize: 12,
          color: _logoError != null
              ? Colors.red.shade300
              : context.colors.mutedText,
        ),
      ),
    ],
  );
}
