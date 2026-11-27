import 'package:material_ui/material_ui.dart';

import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../widgets/watched.dart';

/// The colors a label can be, by index: the project hues.
/// (An index into this is what's stored; new hues go at the end.)
List<Color> get labelPalette => [for (final i in projectHues) projectColors[i]];

/// A label chip's background: its [color] exactly, as in the swatches.
Color labelFill(Color color) => color;

/// A label chip's text (and ✕): near-black, on the [labelFill].
Color labelText(Color color) => const Color(0xFF141414);

/// Indexes into [labelPalette] in the order pickers show them: around the
/// color wheel.
List<int> get labelPickerOrder => [
  for (final p in projectHueWheel) projectHues.indexOf(p),
];

/// A label's color when none was picked: worked out from its text, so it's
/// the same everywhere.
int defaultLabelColor(String label) =>
    label.toLowerCase().codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff) %
    projectHueCount;

/// Each project's label colors (picked when the label was created), so a
/// label chip anywhere shows its color in its task's project: the same
/// colors the labels editor shows and edits ([ProjectLabels.colorOf]).
/// Sits above the navigator, so the task form sees it too.
class LabelColors extends InheritedWidget {
  const LabelColors({super.key, required this.byProject, required super.child});

  /// Keeps [child] supplied with [projects]' label colors as they change.
  static Widget watching(ProjectRepository projects, {required Widget child}) =>
      Watched<List<Project>>(
        watch: projects.watch,
        current: projects.current,
        builder: (context, all) => LabelColors(
          byProject: {for (final p in all) p.id: p.labelColors},
          child: child,
        ),
      );

  /// Palette index by label (lowercased), by project id.
  final Map<String, Map<String, int>> byProject;

  /// [label]'s color in [projectId] (a task's origin): as picked there, or
  /// its default.
  static Color of(BuildContext context, String label, String? projectId) {
    final picked = context
        .dependOnInheritedWidgetOfExactType<LabelColors>()
        ?.byProject[projectId]?[label.toLowerCase()];
    final palette = labelPalette;
    return palette[(picked ?? defaultLabelColor(label)) % palette.length];
  }

  @override
  bool updateShouldNotify(LabelColors old) =>
      old.byProject.length != byProject.length ||
      byProject.entries.any((e) => !_sameMap(old.byProject[e.key], e.value));

  static bool _sameMap(Map<String, int>? a, Map<String, int> b) =>
      a != null &&
      a.length == b.length &&
      a.entries.every((e) => b[e.key] == e.value);
}
