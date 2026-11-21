import 'package:material_ui/material_ui.dart';

import 'project.dart';
import '../app_theme.dart';

/// Asks for a project's name and color. Pass [project] to rename it.
/// Returns null when cancelled.
Future<({String name, int colorIndex})?> showProjectDialog(
  BuildContext context, {
  Project? project,
  int defaultColorIndex = 0,
}) => showDialog(
  context: context,
  // No scrim: the dialog sits directly on the app.
  barrierColor: Colors.transparent,
  builder: (_) =>
      _ProjectDialog(project: project, defaultColorIndex: defaultColorIndex),
);

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({this.project, required this.defaultColorIndex});
  final Project? project;
  final int defaultColorIndex;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final _name = TextEditingController(text: widget.project?.name)
    ..addListener(() => setState(() {}));
  late int _color = widget.project?.colorIndex ?? widget.defaultColorIndex;

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (name: _name.text.trim(), colorIndex: _color));
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
      title: Text(isNew ? 'New project' : 'Rename project'),
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
            Wrap(
              spacing: 10,
              children: [
                for (var i = 0; i < projectColors.length; i++)
                  Semantics(
                    label: 'Color ${i + 1}',
                    selected: i == _color,
                    child: InkWell(
                      onTap: () => setState(() => _color = i),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: projectColors[i],
                          shape: BoxShape.circle,
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: Text(isNew ? 'Create project' : 'Save'),
        ),
      ],
    );
  }
}
