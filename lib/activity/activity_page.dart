import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_repository.dart';
import '../projects/project_logo.dart';
import '../tasks/due_date.dart';
import '../tasks/task.dart';
import '../tasks/task_editor.dart';
import '../tasks/task_repository.dart';
import '../widgets/frosted_bar.dart';
import 'activity.dart';
import 'activity_repository.dart';

/// The Activity view: what other people did to tasks assigned to
/// [profileId], newest first, grouped by day. Opening it marks everything
/// as read; what was unread keeps its dot until you leave.
class ActivityPage extends StatefulWidget {
  const ActivityPage({
    super.key,
    required this.activity,
    required this.tasks,
    required this.profileId,
    required this.projects,
    this.projectRepo,
    this.onOpenTask,
  });

  /// Shows [Task] on the board of the project given (switching to it) and
  /// opens it there. Without it, the task opens over this page.
  final void Function(Task task, String projectId)? onOpenTask;

  /// Where labels are kept, for the task form.
  final ProjectRepository? projectRepo;

  final ActivityRepository activity;
  final TaskRepository tasks;
  final String profileId;

  /// The projects this profile can see, for opening a task.
  final List<Project> projects;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  // Each watch() is a single-listener stream: the list and the
  // mark-as-read listener get one each.
  late Stream<List<Activity>> _stream;
  late final Stream<List<Task>> _tasks = widget.tasks.watch();
  late StreamSubscription<List<Activity>> _markRead;

  /// Unread when shown here: they keep their dot while the page is open.
  final _fresh = <String>{};

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(ActivityPage old) {
    super.didUpdateWidget(old);
    if (old.profileId != widget.profileId) {
      _markRead.cancel();
      _fresh.clear();
      _watch();
    }
  }

  /// Anything unread that arrives while the page is open has been seen:
  /// mark it read (after this frame, outside the stream's delivery).
  void _watch() {
    final id = widget.profileId;
    _stream = widget.activity.watch(id);
    _markRead = widget.activity.watch(id).listen((list) {
      final unread = list.where((a) => a.isUnread).map((a) => a.id);
      if (unread.isEmpty) return;
      setState(() => _fresh.addAll(unread));
      scheduleMicrotask(() => widget.activity.markAllRead(id));
    });
  }

  @override
  void dispose() {
    _markRead.cancel();
    super.dispose();
  }

  void _open(Task task) {
    // The board to open it on: its origin if this profile sees it, else
    // another of its projects that it does.
    final visible = {for (final p in widget.projects) p.id};
    final board = [
      task.originId,
      ...task.multiHomes,
    ].where(visible.contains).firstOrNull;
    if (board == null) return;
    if (widget.onOpenTask case final open?) return open(task, board);
    showTaskEditor(
      context,
      widget.tasks,
      task: task,
      projectId: board,
      projects: widget.projects,
      projectRepo: widget.projectRepo,
    );
  }

  // Notifications, not work: dismissing one (or all) needs no undo.
  void _dismiss(Activity a) => widget.activity.dismiss(a.id);

  void _clearAll() => widget.activity.dismissAll(widget.profileId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Activity>>(
      stream: _stream,
      initialData: widget.activity.current(widget.profileId),
      builder: (context, snap) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Frosted glass, like a project's header.
          FrostedBar(
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Activity',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                ),
                if (snap.requireData.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _clearAll,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: context.colors.text,
                      // The background color, so it reads over an image.
                      backgroundColor: context.colors.surface,
                      side: BorderSide(color: context.colors.cardBorder),
                    ),
                    icon: const Icon(Symbols.clear_all, size: 18),
                    label: const Text('Clear all'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: _tasks,
              initialData: widget.tasks.current(),
              builder: (context, taskSnap) => _list(context, snap.requireData, {
                for (final t in taskSnap.requireData) t.id: t,
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(
    BuildContext context,
    List<Activity> items,
    Map<String, Task> tasks,
  ) {
    if (items.isEmpty) return const _Empty();
    final now = DateTime.now();
    final children = <Widget>[];
    String? day;
    for (final a in items) {
      final label = _dayLabel(a.createdAt.toLocal(), now);
      if (label != day) {
        day = label;
        children.add(_DayHeading(label, first: children.isEmpty));
      }
      final task = tasks[a.taskId];
      children.add(
        _ActivityRow(
          activity: a,
          task: task,
          fresh: _fresh.contains(a.id),
          projects: widget.projects,
          onOpen: task == null ? null : () => _open(task),
          onDismiss: () => _dismiss(a),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        // Readable line length on a wide window.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// "Today", "Yesterday", or the date ("Nov 17, 2026").
String _dayLabel(DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  return switch (days) {
    0 => 'Today',
    1 => 'Yesterday',
    _ => formatDate(day),
  };
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label, {required this.first});
  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(12, first ? 0 : 20, 12, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: context.colors.text,
      ),
    ),
  );
}

/// One activity: who did it, to which task, what changed, and when.
/// Opens the task (unless it's been deleted).
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.task,
    required this.fresh,
    required this.projects,
    required this.onOpen,
    required this.onDismiss,
  });

  final Activity activity;

  /// The task now; null once it's deleted.
  final Task? task;

  /// Unread when the page opened: shows a dot.
  final bool fresh;
  final List<Project> projects;
  final VoidCallback? onOpen;

  /// The ✕: hides it.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scope = ProfilesScope.maybeOf(context);
    final actor = scope?.find(activity.actorId);
    final name = actor?.displayName ?? 'Someone';
    final title = task?.title ?? activity.taskTitle;
    const bold = TextStyle(fontWeight: FontWeight.w400);
    final taskSpan = TextSpan(
      text: title.isEmpty ? 'Untitled task' : title,
      style: bold.copyWith(
        decoration: task == null ? TextDecoration.lineThrough : null,
      ),
    );
    final due = activity.dueAt?.toLocal();
    // "at 5:00 PM", for a task due at a set time.
    final dueTime = due != null && task?.dueTime != null
        ? ' at ${formatTime(due.hour * 60 + due.minute)}'
        : '';
    final sentence = switch (activity.kind) {
      ActivityKind.dueToday => [
        taskSpan,
        TextSpan(text: ' is due today$dueTime'),
      ],
      ActivityKind.overdue => [taskSpan, const TextSpan(text: ' is overdue')],
      final kind => [
        TextSpan(text: name, style: bold),
        TextSpan(
          text: switch (kind) {
            ActivityKind.assigned => ' assigned you ',
            ActivityKind.unassigned => ' unassigned you from ',
            ActivityKind.deleted => ' deleted ',
            _ => ' updated ',
          },
        ),
        taskSpan,
      ],
    };
    final project = projects.where((p) => p.id == task?.originId).firstOrNull;
    final details = [
      if (activity.kind == ActivityKind.updated)
        describeChanges(activity.changes),
      if (activity.kind == ActivityKind.overdue && due != null)
        'Was due ${formatDate(due)}$dueTime',
      if (task == null && activity.kind != ActivityKind.deleted)
        'This task has been deleted',
    ];
    final text = context.colors.text;
    final muted = context.colors.mutedText;
    final when = activity.createdAt.toLocal();

    // Each row on the background color, a few px apart, so it reads over a
    // background image.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: context.colors.surface,
        shape: formShape,
        child: InkWell(
          onTap: onOpen,
          customBorder: formShape,
          hoverColor: context.colors.hover,
          mouseCursor: onOpen == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                // Reminders: a calendar or alarm where a person's avatar goes.
                if (activity.kind.isReminder)
                  SizedBox.square(
                    dimension: 28,
                    child: Icon(
                      activity.kind == ActivityKind.overdue
                          ? Symbols.alarm
                          : Symbols.event,
                      size: 22,
                    ),
                  )
                else if (actor != null)
                  ProfileAvatar(
                    profile: actor,
                    image: scope?.imageOf(actor),
                    size: 28,
                  )
                else
                  Icon(Symbols.account_circle, size: 28, color: muted),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 3,
                    children: [
                      Text.rich(
                        TextSpan(
                          style: TextStyle(fontSize: 13.5, color: text),
                          children: sentence,
                        ),
                      ),
                      for (final d in details)
                        if (d.isNotEmpty)
                          Text(
                            d,
                            style: TextStyle(fontSize: 12.5, color: muted),
                          ),
                      if (project != null)
                        Row(
                          spacing: 6,
                          children: [
                            ProjectIcon(project: project, size: 12),
                            Flexible(
                              child: Text(
                                project.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      Text(
                        formatTime(when.hour * 60 + when.minute),
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      // Unread: a dot in the accent color.
                      SizedBox(
                        width: 8,
                        child: fresh
                            ? Icon(
                                Icons.circle,
                                size: 8,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                      ),
                      // Dismiss (above the row's tap: it doesn't open it).
                      SizedBox.square(
                        dimension: 22,
                        child: IconButton(
                          onPressed: onDismiss,
                          tooltip: 'Dismiss',
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          icon: Icon(Symbols.close, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          Icon(
            Symbols.notifications,
            size: 36,
            color: context.colors.mutedText,
          ),
          const Text(
            'No activity yet',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
          ),
          Text(
            'When someone assigns you a task or changes one that’s '
            'assigned to you, or one of your tasks is due, it shows up '
            'here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.mutedText),
          ),
        ],
      ),
    ),
  );
}
