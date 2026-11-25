import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../layout.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../tasks/task.dart';
import 'project.dart';
import 'project_logo.dart';
import '../app_theme.dart';

/// Solid sidebar fill; the traffic lights sit on top of it.

/// Lists every project. Selecting one shows its tasks; dropping a dragged
/// task card on one adds the task to that project too.
class ProjectSidebar extends StatelessWidget {
  const ProjectSidebar({
    super.key,
    required this.projects,
    required this.tasks,
    required this.selectedId,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDropTask,
    required this.onOpenSettings,
    required this.profile,
    required this.onOpenProfile,
    required this.activitySelected,
    required this.unreadActivity,
    required this.onOpenActivity,
    this.personal,
    this.profileImage,
    this.syncStatus,
  });

  /// The shared (company) projects.
  final List<Project> projects;

  /// The current profile's personal project, listed above the shared ones.
  final Project? personal;

  /// Whoever is using the app: their avatar sits next to Settings.
  final Profile profile;
  final File? profileImage;
  final VoidCallback onOpenProfile;

  /// The Activity view is showing (no project is selected then).
  final bool activitySelected;

  /// How many activities are unread, shown next to Activity.
  final int unreadActivity;
  final VoidCallback onOpenActivity;

  /// All tasks, for each project's count of tasks not checked off.
  final List<Task> tasks;

  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;

  /// The pencil on a project row: its name, color and Delete.
  final ValueChanged<Project> onEdit;

  /// A task card was dropped on a project it isn't in yet.
  final void Function(Task task, String projectId) onDropTask;

  /// The Settings button at the bottom.
  final VoidCallback onOpenSettings;

  /// The sync status icon, just left of Settings (left out in tests).
  final Widget? syncStatus;

  int _taskCount(String projectId) => tasks
      .where((t) => t.isIn(projectId) && !t.isCompletedIn(projectId))
      .length;

  @override
  Widget build(BuildContext context) {
    // Flush with the window's left, top and bottom edges, running up behind
    // the traffic lights; a hard line separates it from the tasks.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.colors.cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Activity, the personal project and the Projects heading stay
          // put; only the projects below them scroll.
          _pinned(context),
          Expanded(child: _projectList(context)),
          // Settings, pinned to the bottom below a line.
          Container(
            padding: const EdgeInsets.all(8),
            // The same line color as the cards and list table.
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.colors.cardBorder)),
            ),
            // The profile's avatar at the left; sync status and Settings at
            // the right.
            child: Row(
              spacing: 4,
              children: [
                Tooltip(
                  message: profile.displayName,
                  child: InkWell(
                    onTap: onOpenProfile,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ProfileAvatar(
                        profile: profile,
                        image: profileImage,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                ?syncStatus,
                // Just the icon, at the right edge.
                IconButton(
                  tooltip: 'Settings',
                  iconSize: 17,
                  onPressed: onOpenSettings,
                  icon: Icon(Symbols.tune),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Above the scrolling projects: Activity, the personal project and
  /// the Projects heading.
  Widget _pinned(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, titleBarHeight + 8, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // What others did to your tasks, at the top.
          _SidebarItem(
            leading: Icon(Symbols.notifications, size: 16),
            label: 'Activity',
            count: unreadActivity,
            countIsBadge: true,
            selected: activitySelected,
            onTap: onOpenActivity,
          ),
          // The profile's own project, above the shared ones. Nothing to
          // edit: it can't be renamed, recolored or deleted.
          if (personal case final p?) ...[
            _SidebarItem(
              key: ValueKey(p.id),
              leading: Icon(Symbols.person, size: 16),
              label: p.name,
              count: _taskCount(p.id),
              selected: !activitySelected && selectedId == p.id,
              onTap: () => onSelect(p.id),
              acceptsTask: (t) => !t.isIn(p.id),
              onDropTask: (t) => onDropTask(t, p.id),
            ),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'PROJECTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: context.colors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'New project',
                  iconSize: 17,
                  visualDensity: VisualDensity.compact,
                  onPressed: onCreate,
                  icon: Icon(Symbols.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The shared projects, scrolling on their own.
  Widget _projectList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        for (final p in projects)
          _SidebarItem(
            key: ValueKey(p.id),
            leading: ProjectIcon(project: p),
            label: p.name,
            count: _taskCount(p.id),
            selected: !activitySelected && selectedId == p.id,
            onTap: () => onSelect(p.id),
            acceptsTask: (t) => !t.isIn(p.id),
            onDropTask: (t) => onDropTask(t, p.id),
            action: _EditButton(onPressed: () => onEdit(p)),
          ),
        if (projects.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(10, 4, 10, 0),
            child: Text(
              'No projects yet',
              style: TextStyle(fontSize: 13, color: context.colors.mutedText),
            ),
          ),
      ],
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    super.key,
    required this.leading,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.acceptsTask,
    this.onDropTask,
    this.countIsBadge = false,
    this.action,
  });

  final Widget leading;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Whether a dragged task card can be dropped here; null for rows that
  /// take no drops (Activity).
  final bool Function(Task)? acceptsTask;
  final ValueChanged<Task>? onDropTask;

  /// Shows [count] as an accent badge (unread activity) rather than plain
  /// muted text (a project's open tasks).
  final bool countIsBadge;

  /// A button shown in place of the count on hover (a project's pencil).
  final Widget? action;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => widget.acceptsTask?.call(d.data) ?? false,
      onAcceptWithDetails: (d) => widget.onDropTask?.call(d.data),
      builder: (context, candidates, _) {
        final dropping = candidates.isNotEmpty;
        final action = _hover ? widget.action : null;
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            color: dropping
                ? context.colors.dropHighlight
                : widget.selected
                ? Theme.of(context).colorScheme.primary
                : context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: formRadius,
              side: dropping
                  ? BorderSide(color: context.colors.mutedText)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: formRadius,
              // No ripple or press shade: the selected fill shows the click.
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: SizedBox(
                height: 34,
                child: Padding(
                  padding: const EdgeInsets.only(left: 10, right: 4),
                  child: Row(
                    spacing: 10,
                    children: [
                      SizedBox(width: 18, child: Center(child: widget.leading)),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            // Readable on the accent when selected.
                            color: widget.selected && !dropping
                                ? Theme.of(context).colorScheme.onPrimary
                                : null,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (action != null)
                        action
                      else if (widget.count > 0 && widget.countIsBadge)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _Badge(
                            count: widget.count,
                            onAccent: widget.selected && !dropping,
                          ),
                        )
                      else if (widget.count > 0)
                        // In the light border line, like the cards'.
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          height: sidebarBoxSize,
                          constraints: const BoxConstraints(
                            minWidth: sidebarBoxSize,
                          ),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            borderRadius: formRadius,
                            border: Border.all(
                              color: widget.selected && !dropping
                                  ? Theme.of(context).colorScheme.onPrimary
                                        .withValues(alpha: 0.4)
                                  : context.colors.cardBorder,
                            ),
                          ),
                          child: Text(
                            '${widget.count}',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.selected && !dropping
                                  ? Theme.of(context).colorScheme.onPrimary
                                        .withValues(alpha: 0.75)
                                  : context.colors.mutedText,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// An unread count: the number on an accent fill (or, on the selected
/// row's accent fill, the reverse), so it stands out from task counts.
class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.onAccent});
  final int count;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onAccent ? scheme.onPrimary : scheme.primary,
        borderRadius: formRadius,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: onAccent ? scheme.primary : scheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The pencil on a project row: opens the project's dialog (name, color,
/// and Delete).
/// The side of a project row's count box and its edit button.
const sidebarBoxSize = 22.0;

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    // The same size as the count box it replaces.
    child: IconButton(
      tooltip: 'Edit project',
      iconSize: 14,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: sidebarBoxSize,
        height: sidebarBoxSize,
      ),
      style: context.colors.menuButtonStyle.copyWith(
        minimumSize: const WidgetStatePropertyAll(Size.square(sidebarBoxSize)),
        fixedSize: const WidgetStatePropertyAll(Size.square(sidebarBoxSize)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onPressed,
      icon: Icon(Symbols.edit),
    ),
  );
}
