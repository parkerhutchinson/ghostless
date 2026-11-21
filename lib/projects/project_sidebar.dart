import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../layout.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../tasks/task.dart';
import 'project.dart';
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
    required this.onRename,
    required this.onDelete,
    required this.onDropTask,
    required this.onOpenSettings,
    required this.profile,
    required this.onOpenProfile,
    required this.activitySelected,
    required this.unreadActivity,
    required this.onOpenActivity,
    this.personal,
    this.profileImage,
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
  final ValueChanged<Project> onRename;
  final ValueChanged<Project> onDelete;

  /// A task card was dropped on a project it isn't in yet.
  final void Function(Task task, String projectId) onDropTask;

  /// The Settings button at the bottom.
  final VoidCallback onOpenSettings;

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
          Expanded(child: _projectList(context)),
          // Settings, pinned to the bottom below a line.
          Container(
            padding: const EdgeInsets.all(8),
            // The same line color as the cards and list table.
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.colors.cardBorder)),
            ),
            // The profile's avatar at the left, Settings at the right.
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

  Widget _projectList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, titleBarHeight + 8, 8, 8),
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
        // The profile's own project, above the shared ones. It can be
        // renamed, but not deleted.
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
            menu: (onOpenChanged) => _ProjectMenu(
              onRename: () => onRename(p),
              onOpenChanged: onOpenChanged,
            ),
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
        for (final p in projects)
          _SidebarItem(
            key: ValueKey(p.id),
            leading: Icon(Icons.circle, size: 10, color: p.color),
            label: p.name,
            count: _taskCount(p.id),
            selected: !activitySelected && selectedId == p.id,
            onTap: () => onSelect(p.id),
            acceptsTask: (t) => !t.isIn(p.id),
            onDropTask: (t) => onDropTask(t, p.id),
            menu: (onOpenChanged) => _ProjectMenu(
              onRename: () => onRename(p),
              onDelete: () => onDelete(p),
              onOpenChanged: onOpenChanged,
            ),
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
    this.menu,
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

  /// The ⋯ menu, shown on hover. Builds it with a callback that reports
  /// whether the menu is open.
  final Widget Function(ValueChanged<bool> onOpenChanged)? menu;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => widget.acceptsTask?.call(d.data) ?? false,
      onAcceptWithDetails: (d) => widget.onDropTask?.call(d.data),
      builder: (context, candidates, _) {
        final dropping = candidates.isNotEmpty;
        // Only on hover; kept while its menu is open (the pointer has left the
        // row by then), or the menu's choice would be dropped.
        final showMenu = widget.menu != null && (_hover || _menuOpen);
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
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (showMenu)
                        widget.menu!((open) => setState(() => _menuOpen = open))
                      else if (widget.count > 0 && widget.countIsBadge)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: _Badge(
                            count: widget.count,
                            onAccent: widget.selected && !dropping,
                          ),
                        )
                      else if (widget.count > 0)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            '${widget.count}',
                            style: TextStyle(
                              fontSize: 12,
                              color: widget.selected && !dropping
                                  ? Theme.of(context).colorScheme.onPrimary
                                        .withValues(alpha: 0.75)
                                  : context.colors.mutedText,
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
          fontWeight: FontWeight.w600,
          color: onAccent ? scheme.primary : scheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({
    required this.onRename,
    this.onDelete,
    required this.onOpenChanged,
  });
  final VoidCallback onRename;

  /// Null for a personal project, which can't be deleted.
  final VoidCallback? onDelete;
  final ValueChanged<bool> onOpenChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Project options',
      iconSize: 17,
      padding: EdgeInsets.zero,
      style: context.colors.menuButtonStyle,
      icon: Icon(Symbols.more_horiz),
      onOpened: () => onOpenChanged(true),
      onCanceled: () => onOpenChanged(false),
      onSelected: (action) {
        onOpenChanged(false);
        action();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: onRename,
          child: const ListTile(
            dense: true,
            leading: Icon(Symbols.edit, size: 18),
            title: Text('Rename…'),
          ),
        ),
        if (onDelete case final onDelete?)
          PopupMenuItem(
            value: onDelete,
            child: ListTile(
              dense: true,
              leading: Icon(
                Symbols.delete,
                size: 18,
                color: Colors.red.shade300,
              ),
              title: Text(
                'Delete project',
                style: TextStyle(color: Colors.red.shade300),
              ),
            ),
          ),
      ],
    );
  }
}
