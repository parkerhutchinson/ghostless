import 'dart:math' as math;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../comments/task_comments.dart' show commentTime;
import '../profiles/profiles_scope.dart';
import '../reminders/reminders.dart';
import '../tasks/rich_text/rich_text_editor.dart';
import '../tasks/task.dart';
import '../tasks/task_board.dart' show headerButtonFill;
import '../widgets/bottom_fade.dart';
import '../widgets/frosted_bar.dart';
import 'project.dart';
import 'project_logo.dart';
import 'project_stats.dart';

/// Space around the dashboard: the list view's side padding.
const _pagePadding = 24.0;

/// Between one section and the next heading. Within a section, tiles
/// touch: they share their borders, like the list view's rows.
const _sectionGap = 16.0;

/// A column tile is never narrower than this; the grid fits as many to a
/// row as it can.
const _minColumnTile = 220.0;

/// The most column tiles to a row, however wide the pane.
const _maxPerRow = 4;

/// The dashboard's width at most, centered in the pane: the list view's
/// ([listMaxWidth], which includes the side padding).
const _maxWidth = 1250.0 - _pagePadding * 2;

/// How the big numbers count up (and the total's bar fills): over the
/// first part of the dashboard's opening animation.
const _countUp = Interval(0, 0.6, curve: Curves.easeOutCubic);

/// Below this width, the top tiles stack instead of sitting side by side.
const _stackBelow = 620.0;

/// A project's dashboard: what it's about (its description), how many
/// tasks it has, who they're assigned to, and per column, how many are
/// done.
class ProjectDashboard extends StatefulWidget {
  const ProjectDashboard({
    super.key,
    required this.project,
    required this.tasks,
    this.onEdit,
    this.entrance,
    this.projects = const [],
    this.onOpenTask,
  });

  /// Opens a task on a board (a reminder's, clicked on a personal
  /// dashboard).
  final void Function(Task task, String projectId)? onOpenTask;

  /// Every project: on a personal dashboard, the shared ones its owner
  /// has tasks in are listed with their numbers there.
  final List<Project> projects;

  /// The page's fade-in: once it has finished, the rings fill in. Without
  /// one, they fill in as soon as the dashboard shows.
  final Animation<double>? entrance;

  final Project project;

  /// Every task (the ones on other boards are skipped).
  final List<Task> tasks;

  /// Opens the project's dialog, where the description is written; null
  /// when the project can't be edited.
  final VoidCallback? onEdit;

  @override
  State<ProjectDashboard> createState() => _ProjectDashboardState();
}

class _ProjectDashboardState extends State<ProjectDashboard>
    with SingleTickerProviderStateMixin {
  /// The opening animation, 0 to 1, after the page has faded in: the
  /// total counts up ([_TotalTile]) and the rings fill in ([_ColumnTile]:
  /// each one starts a little after the one before).
  late final _rings = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );

  @override
  void initState() {
    super.initState();
    final entrance = widget.entrance;
    if (entrance == null || entrance.isCompleted) {
      _rings.forward();
    } else {
      entrance.addStatusListener(_onEntrance);
    }
  }

  void _onEntrance(AnimationStatus status) {
    if (!status.isCompleted) return;
    widget.entrance?.removeStatusListener(_onEntrance);
    if (mounted) _rings.forward();
  }

  @override
  void dispose() {
    widget.entrance?.removeStatusListener(_onEntrance);
    _rings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ProjectDashboard(:project, :tasks, :onEdit) = widget;
    final stats = projectStats(project, tasks);
    // A personal project can't be edited, and everything in it is its
    // owner's: no description, no people.
    final personal = project.isPersonal;
    // The bottom fades out, as on every page that scrolls to the
    // window's bottom.
    return BottomFadeScrollView(
      padding: EdgeInsets.fromLTRB(
        _pagePadding,
        // None at the top, like the list view: the first heading sits
        // right under the page header.
        0,
        _pagePadding,
        // Room for the last tiles to scroll clear of the fade.
        bottomFadeHeight,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!personal) ...[
                _SectionHeader(
                  'Description',
                  action: onEdit == null
                      ? null
                      : (
                          icon: Symbols.edit,
                          tooltip: 'Edit description',
                          onPressed: onEdit,
                        ),
                ),
                // Half the width each, so the text keeps to a readable
                // line length: the description, then the project's mark.
                LayoutBuilder(
                  builder: (context, constraints) => _Cells(
                    perRow: constraints.maxWidth < _stackBelow ? 1 : 2,
                    children: [
                      _DescriptionView(
                        key: ValueKey(project.description),
                        markdown: project.description,
                        onEdit: onEdit,
                      ),
                      _MarkTile(project: project),
                    ],
                  ),
                ),
                const SizedBox(height: _sectionGap),
              ],
              const _SectionHeader('Overview'),
              _TopRow(
                total: _TotalTile(stats: stats, intro: _rings),
                // A personal project: its owner, instead of who's assigned.
                people: personal
                    ? _ProfileTile(profileId: project.ownerId)
                    : _PeopleTile(stats: stats, intro: _rings),
              ),
              const SizedBox(height: _sectionGap),
              // A personal dashboard: its owner's reminders still to go
              // off, on any board.
              if (project.ownerId case final owner?) ...[
                Builder(
                  builder: (context) {
                    final reminders = activeReminders(
                      tasks,
                      profileId: owner,
                      now: DateTime.now(),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader('Reminders', count: reminders.length),
                        _Cells(
                          perRow: 1,
                          children: [
                            if (reminders.isEmpty)
                              const _NoReminders()
                            else
                              for (final r in reminders)
                                _ReminderRow(
                                  reminder: r,
                                  project: widget.projects
                                      .where((p) => p.id == r.task.originId)
                                      .firstOrNull,
                                  onOpen: widget.onOpenTask == null
                                      ? null
                                      : () => widget.onOpenTask!(
                                          r.task,
                                          r.task.originId,
                                        ),
                                ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: _sectionGap),
              ],
              _SectionHeader(
                'Completed by column',
                count: stats.columns.length,
              ),
              _ColumnGrid(stats: stats, rings: _rings),
              // A personal dashboard: its owner's tasks on the shared
              // boards too.
              if (project.ownerId case final owner?) ...[
                const SizedBox(height: _sectionGap),
                Builder(
                  builder: (context) {
                    final elsewhere = assignedElsewhere(
                      widget.projects,
                      tasks,
                      owner,
                      now: DateTime.now(),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SectionHeader(
                          'Assigned to you in other projects',
                          count: elsewhere.length,
                        ),
                        _AssignedGrid(stats: elsewhere, rings: _rings),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A section's heading, styled like a board column's (see
/// [ColumnHeader]): on frosted glass with a line under it, the title, an
/// optional count beside it and an optional button at the right.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title, {this.count, this.action});
  final String title;
  final int? count;
  final ({IconData icon, String tooltip, VoidCallback onPressed})? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.zero,
    // No line: the tiles' top border is right under it.
    child: FrostedHeader(
      line: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // Title and count take all the room left of the button, as
            // on a column, so the button is at the right edge.
            Expanded(
              child: Row(
                spacing: 8,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (count case final count?)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: formRadius,
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.text,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // The column heading's button size, so every heading is as
            // tall as a column's, with or without one.
            SizedBox(
              height: 26,
              child: switch (action) {
                final a? => IconButton(
                  tooltip: a.tooltip,
                  iconSize: 17,
                  padding: EdgeInsets.zero,
                  style: headerButtonFill(context).merge(
                    IconButton.styleFrom(
                      fixedSize: const Size(26, 26),
                      minimumSize: const Size(26, 26),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  onPressed: a.onPressed,
                  icon: Icon(a.icon),
                ),
                null => null,
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// A box on the card shade, square like the list view's: a cell of a
/// [_Cells]. It draws only its right and bottom edges, and the group draws
/// the top and left, so neighbours share one line.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.fill,
  });
  final Widget child;
  final EdgeInsets padding;

  /// The card shade unless given.
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: context.colors.cardBorder);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? context.colors.card,
        border: Border(right: line, bottom: line),
      ),
      child: child,
    );
  }
}

/// Tiles packed edge to edge: rows of [perRow] cells, each as wide as the
/// rest and as tall as the tallest in its row; a short last row leaves the
/// rest of it empty. Draws the left border (and the first row's top
/// border) the cells don't.
class _Cells extends StatelessWidget {
  const _Cells({required this.perRow, required this.children});
  final int perRow;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: context.colors.cardBorder);
    return Container(
      decoration: BoxDecoration(border: Border(left: line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var start = 0; start < children.length; start += perRow)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = start; i < start + perRow; i++)
                    Expanded(
                      child: i >= children.length
                          ? const SizedBox()
                          // The first row's cells draw the top edge, so
                          // it runs only as far as they do.
                          : start == 0
                          ? DecoratedBox(
                              // Over the tile's fill, not under it.
                              position: DecorationPosition.foreground,
                              decoration: BoxDecoration(
                                border: Border(top: line),
                              ),
                              child: children[i],
                            )
                          : children[i],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The total and the people side by side (as tall as each other), or
/// stacked when the pane is narrow.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.total, this.people});
  final Widget total;
  final Widget? people;

  @override
  Widget build(BuildContext context) {
    final people = this.people;
    if (people == null) return _Cells(perRow: 1, children: [total]);
    return LayoutBuilder(
      builder: (context, constraints) => _Cells(
        perRow: constraints.maxWidth < _stackBelow ? 1 : 2,
        children: [total, people],
      ),
    );
  }
}

/// The big number: every task on the board, with how many are done.
class _TotalTile extends StatelessWidget {
  const _TotalTile({required this.stats, required this.intro});
  final ProjectStats stats;

  /// The dashboard's opening animation (0 to 1): the number counts up
  /// and the bar fills over the first part of it, alongside the first
  /// ring.
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final fraction = stats.total == 0 ? 0.0 : stats.done / stats.total;
    // A change later on (a task done) slides the bar to its new length.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: fraction),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      builder: (context, shownFraction, _) => AnimatedBuilder(
        animation: intro,
        builder: (context, _) {
          final p = _countUp.transform(intro.value);
          int counted(int n) => (n * p).round();
          final bar = shownFraction * p;
          return _Tile(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Beside the people tile (as tall as it), the bar sits at
              // the bottom.
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _BigNumber(label: 'Total tasks', value: counted(stats.total)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // Done out of all, as a bar as thick as the rings.
                    SizedBox(
                      height: _RingPainter.stroke,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: colors.divider),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: bar,
                            child: ColoredBox(color: accent),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      // The final numbers from the start: only the big
                      // number and the bar animate.
                      '${stats.done} done · ${stats.open} open'
                      '${stats.total == 0 ? '' : ' · ${(fraction * 100).round()}% complete'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.mutedText,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A tile's headline: a small label over a big number.
class _BigNumber extends StatelessWidget {
  const _BigNumber({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(fontSize: 12, color: context.colors.mutedText),
      ),
      Text(
        '$value',
        style: TextStyle(
          fontSize: 64,
          height: 1.15,
          fontWeight: FontWeight.w700,
          // Tighter: at this size the digits sit too far apart.
          letterSpacing: -2.5,
          color: context.colors.text,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _PeopleTile extends StatelessWidget {
  const _PeopleTile({required this.stats, required this.intro});
  final ProjectStats stats;

  /// The dashboard's opening animation: the number counts up like the
  /// total's, and the avatars fade in one at a time.
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    // Ids that match no profile show as unassigned, as on the cards.
    final people = [
      for (final a in stats.assignees)
        if (scope?.find(a.assigneeId) case final profile?) (profile, a),
    ];
    final unassigned =
        stats.unassigned +
        stats.assignees
            .where((a) => scope?.find(a.assigneeId) == null)
            .fold(0, (n, a) => n + a.total);
    final top = topCompleter([for (final (_, a) in people) a]);
    final topProfile = scope?.find(top?.assigneeId);
    final muted = TextStyle(fontSize: 12, color: colors.mutedText);
    return _Tile(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // As on the total beside it: the summary sits at the bottom.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedBuilder(
                animation: intro,
                builder: (context, _) => _BigNumber(
                  label: 'People assigned',
                  value: (people.length * _countUp.transform(intro.value))
                      .round(),
                ),
              ),
              const SizedBox(height: 12),
              if (people.isEmpty)
                Text('No one is assigned to a task here yet.', style: muted)
              else
                _AvatarStack(
                  people: [for (final (profile, _) in people) profile],
                  intro: intro,
                ),
            ],
          ),
          if (people.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  if ((top, topProfile) case (final top?, final profile?))
                    Row(
                      spacing: 8,
                      children: [
                        ProfileAvatar(
                          profile: profile,
                          image: scope!.imageOf(profile),
                          size: 20,
                        ),
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: profile.displayName,
                                  style: TextStyle(
                                    color: colors.text,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text:
                                      ' has completed the most: '
                                      '${top.done} task${top.done == 1 ? '' : 's'}',
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: muted,
                          ),
                        ),
                      ],
                    )
                  else
                    Text('No one has completed a task here yet.', style: muted),
                  if (unassigned > 0)
                    Text(
                      '$unassigned task${unassigned == 1 ? '' : 's'} unassigned',
                      style: muted,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// On a personal dashboard, beside the total: whose project it is, with
/// their photo, name, job and description.
class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profileId});
  final String? profileId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final profile = scope?.find(profileId);
    if (profile == null) return const _Tile(child: SizedBox.shrink());
    return _Tile(
      padding: const EdgeInsets.all(20),
      // The avatar centered in the tile's height (which is the total's,
      // beside it); the name at the top, level with "Total tasks".
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 24,
        children: [
          Center(
            child: ProfileAvatar(
              profile: profile,
              image: scope!.imageOf(profile),
              size: 128,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  profile.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    // Snug when a long name wraps to a second line.
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 28,
                  runSpacing: 8,
                  children: [
                    _ProfileField('Job title', profile.jobTitle),
                    _ProfileField('Department', profile.department),
                  ],
                ),
                const SizedBox(height: 4),
                _ProfileField('About', profile.description, maxLines: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One of a profile's fields: a small label over its value, or "Not set".
class _ProfileField extends StatelessWidget {
  const _ProfileField(this.label, this.value, {this.maxLines = 1});
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = value.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: colors.mutedText)),
        Text(
          text.isEmpty ? 'Not set' : text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: text.isEmpty ? colors.placeholder : colors.text,
          ),
        ),
      ],
    );
  }
}

/// The people's avatars in a row, each overlapping the one before, up to
/// [max]; past that, a "+N" for the rest. Names show on hover.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.people, required this.intro});
  final List<Profile> people;

  /// The dashboard's opening animation: each avatar (then the "+N")
  /// fades in [_stagger] after the one before, left to right, taking
  /// [_fade] of it.
  final Animation<double> intro;
  static const _stagger = 0.06, _fade = 0.25;

  double _opacity(int slot, double t) => Interval(
    slot * _stagger,
    slot * _stagger + _fade,
    curve: Curves.easeOut,
  ).transform(t);

  static const max = 8;
  static const _size = 34.0;

  /// How much of each avatar the next one covers.
  static const _overlap = 10.0;

  /// The tile-colored ring around each, so overlapping ones stay apart.
  static const _ring = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final shown = people.take(max).toList();
    final more = people.length - shown.length;
    final slots = shown.length + (more > 0 ? 1 : 0);
    const step = _size - _overlap;
    Widget ringed(Widget child) => Container(
      width: _size,
      height: _size,
      padding: const EdgeInsets.all(_ring),
      decoration: BoxDecoration(color: colors.card, shape: BoxShape.circle),
      child: child,
    );
    return AnimatedBuilder(
      animation: intro,
      builder: (context, _) => SizedBox(
        width: _size + step * (slots - 1),
        height: _size,
        child: Stack(
          children: [
            for (final (i, profile) in shown.indexed)
              Positioned(
                left: step * i,
                child: Opacity(
                  opacity: _opacity(i, intro.value),
                  child: Tooltip(
                    message: profile.displayName,
                    child: ringed(
                      ProfileAvatar(
                        profile: profile,
                        image: scope?.imageOf(profile),
                        size: _size - _ring * 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (more > 0)
              Positioned(
                left: step * shown.length,
                child: Opacity(
                  opacity: _opacity(shown.length, intro.value),
                  child: Tooltip(
                    message: [for (final p in people.skip(max)) p.displayName]
                        .join('\n'),
                    child: ringed(
                      Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.divider,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '+$more',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
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
}

/// A tile per column, as many to a row as fit.
class _ColumnGrid extends StatelessWidget {
  const _ColumnGrid({required this.stats, required this.rings});
  final ProjectStats stats;
  final Animation<double> rings;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _Cells(
      perRow: (constraints.maxWidth / _minColumnTile).floor().clamp(
        1,
        _maxPerRow,
      ),
      children: [
        for (final (i, c) in stats.columns.indexed)
          _RingTile(
            title: _TileTitle(c.column.title),
            name: c.column.title,
            total: c.total,
            done: c.done,
            rings: rings,
            index: i,
          ),
      ],
    ),
  );
}

/// One column: its name, a ring of done against not done, and the counts.
/// A ring of done against open, under a title, with the counts below
/// (and an optional [footer]): a column's tasks, or someone's tasks in a
/// project.
class _RingTile extends StatelessWidget {
  const _RingTile({
    required this.title,
    required this.name,
    required this.total,
    required this.done,
    required this.rings,
    required this.index,
    this.footer,
  });

  /// Shown at the top; [name] is what it's read out as.
  final Widget title;
  final String name;
  final int total;
  final int done;
  final Widget? footer;

  int get _open => total - done;
  double get _doneFraction => total == 0 ? 0 : done / total;

  /// The dashboard's rings filling in (0 to 1). This one's share starts
  /// [_stagger] after the one before it, left to right.
  final Animation<double> rings;
  final int index;

  /// How far into [rings] each ring starts after the last, and how much of
  /// it one ring takes to fill (later rings start no later than
  /// [_lastStart]).
  static const _stagger = 0.08, _lastStart = 0.4, _fill = 0.6;

  /// How far this ring has filled in, 0 to 1, at [t] of [rings].
  double _progress(double t) {
    final start = math.min(index * _stagger, _lastStart);
    return Interval(
      start,
      start + _fill,
      curve: Curves.easeOutCubic,
    ).transform(t);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final empty = total == 0;
    return _Tile(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          title,
          Center(
            child: Semantics(
              label: '$done of $total done in $name',
              // A change later on (a task done) slides the ring to its
              // new value; on top of that, it fills in on opening.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: _doneFraction),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, target, _) => AnimatedBuilder(
                  animation: rings,
                  builder: (context, _) {
                    final fraction = target * _progress(rings.value);
                    return SizedBox.square(
                      dimension: 160,
                      child: CustomPaint(
                        painter: _RingPainter(
                          fraction: fraction,
                          done: accent,
                          open: colors.divider,
                        ),
                        child: Center(
                          child: Text(
                            empty ? '–' : '${(fraction * 100).round()}%',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                              color: empty ? colors.mutedText : colors.text,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 14,
            children: [
              _Legend(color: accent, label: 'Done', count: done),
              _Legend(color: colors.divider, label: 'Open', count: _open),
            ],
          ),
          ?footer,
        ],
      ),
    );
  }
}

/// A ring tile's title: one line, cut short if long.
class _TileTitle extends StatelessWidget {
  const _TileTitle(this.text, {this.leading});
  final String text;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 8,
    children: [
      ?leading,
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.colors.text,
          ),
        ),
      ),
    ],
  );
}

/// On a personal dashboard: per shared project, the owner's tasks there.
class _AssignedGrid extends StatelessWidget {
  const _AssignedGrid({required this.stats, required this.rings});
  final List<AssignedStats> stats;
  final Animation<double> rings;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: context.colors.mutedText);
    if (stats.isEmpty) {
      return _Cells(
        perRow: 1,
        children: [
          _Tile(
            child: Text(
              'You aren\'t assigned to any tasks in other projects.',
              style: muted,
            ),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _Cells(
        perRow: (constraints.maxWidth / _minColumnTile).floor().clamp(
          1,
          _maxPerRow,
        ),
        children: [
          for (final (i, a) in stats.indexed)
            _RingTile(
              title: _TileTitle(
                a.project.name,
                leading: ProjectIcon(project: a.project, size: 16),
              ),
              name: a.project.name,
              total: a.total,
              done: a.done,
              rings: rings,
              index: i,
              // Always a line, so the tiles in a row line up.
              footer: Center(
                child: Text(
                  a.overdue == 0 ? 'Nothing overdue' : '${a.overdue} overdue',
                  style: muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.count,
  });
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 6,
    children: [
      // A key, not a control: a small square in the ring's color.
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: formRadius),
      ),
      Text(
        '$label $count',
        style: TextStyle(fontSize: 12, color: context.colors.mutedText),
      ),
    ],
  );
}

/// A ring: [open] all the way round, [done] over it from the top,
/// clockwise, for [fraction] of the way.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.done,
    required this.open,
  });
  final double fraction;
  final Color done;
  final Color open;

  /// The ring's thickness (and the total's bar's).
  static const stroke = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = open);
    if (fraction > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * fraction.clamp(0, 1),
        false,
        paint..color = done,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.done != done || old.open != open;
}

/// The project's logo, or without one its color as a square, centered in
/// a tile beside the description.
class _MarkTile extends StatelessWidget {
  const _MarkTile({required this.project});
  final Project project;

  static const _size = 120.0;

  @override
  Widget build(BuildContext context) => _Tile(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: switch (project.logo) {
        final logo? => LogoImage(logo: logo, size: _size),
        null => ProjectIcon.of(color: project.color, size: _size),
      },
    ),
  );
}

/// The project's description, as written in the project dialog: drawn
/// with the editor's own formatting (headings, lists, bold…), read only.
/// Selectable, to copy from. Rebuilt (by key) when it changes.
class _DescriptionView extends StatefulWidget {
  const _DescriptionView({super.key, required this.markdown, this.onEdit});
  final String markdown;
  final VoidCallback? onEdit;

  @override
  State<_DescriptionView> createState() => _DescriptionViewState();
}

class _DescriptionViewState extends State<_DescriptionView> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.markdown.trim().isEmpty) {
      // The note where the text would start (the same padding), and the
      // button in the bottom-right corner.
      return _Tile(
        // The note where the text starts when there is one (20 down).
        padding: const EdgeInsets.fromLTRB(16, 20, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'No description yet.',
              style: TextStyle(fontSize: 13, color: colors.mutedText),
            ),
            const Spacer(),
            if (widget.onEdit case final onEdit?)
              Align(
                alignment: Alignment.bottomRight,
                child: TextButton(
                  onPressed: onEdit,
                  child: const Text('Add description'),
                ),
              ),
          ],
        ),
      );
    }
    return _Tile(
      // Roomy above and below (more than the sides).
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      // Read only; its links open.
      child: RichTextView(markdown: widget.markdown),
    );
  }
}

/// One reminder on a personal dashboard: a bell, the task and its
/// project, then when it goes off and how long before it's due. Opens the
/// task when clicked.
class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder, this.project, this.onOpen});
  final ActiveReminder reminder;
  final Project? project;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (:task, :at) = reminder;
    final title = task.title.trim();
    final project = this.project;
    return Material(
      color: colors.card,
      child: InkWell(
        onTap: onOpen,
        hoverColor: colors.rowHover,
        splashFactory: NoSplash.splashFactory,
        child: _Tile(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          // Transparent over the ink, so the hover shows.
          fill: Colors.transparent,
          child: Row(
            spacing: 12,
            children: [
              Icon(Symbols.notifications, size: 18, color: colors.text),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      title.isEmpty ? 'Untitled task' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: colors.text),
                    ),
                    if (project != null)
                      Row(
                        spacing: 6,
                        children: [
                          ProjectIcon.of(
                            color: project.color,
                            logo: project.logo,
                            size: 12,
                          ),
                          Flexible(
                            child: Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.mutedText,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 2,
                children: [
                  Text(
                    commentTime(at, DateTime.now()),
                    style: TextStyle(fontSize: 13, color: colors.text),
                  ),
                  Text(
                    reminderLabel(task.reminder),
                    style: TextStyle(fontSize: 12, color: colors.mutedText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Reminders section with none set.
class _NoReminders extends StatelessWidget {
  const _NoReminders();

  @override
  Widget build(BuildContext context) => _Tile(
    child: Text(
      'No reminders coming up. Set one on a task assigned to you, in the '
      'task form under Reminder.',
      style: TextStyle(fontSize: 12.5, color: context.colors.mutedText),
    ),
  );
}
