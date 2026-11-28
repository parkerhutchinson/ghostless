import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../comments/task_comments.dart' show TaskComments;
import '../tasks/due_date.dart' show formatMonthDay, formatTime;
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../tasks/rich_text/rich_text_editor.dart';
import '../tasks/task_card.dart' show TaskTable;
import '../widgets/bottom_fade.dart';
import '../widgets/pane_dialog.dart';
import '../widgets/watched.dart';
import 'status_update.dart';
import 'status_updates_scope.dart';

/// Opens [project]'s status: on the left, the updates posted so far
/// (newest first); on the right, a new one to write, with its status and
/// what's happening. Posting it sets the project's status.
Future<void> showStatusDialog(
  BuildContext context, {
  required Project project,
}) => showPaneDialog(
  // Centered in the view pane it's opened from.
  context: context,
  builder: (_) => _StatusDialog(project: project),
);

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.project});
  final Project project;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  /// Starts at the project's status, so a plain update keeps it.
  late ProjectStatus? _status = widget.project.status;
  final _body = RichTextController.fromMarkdown('');

  @override
  void initState() {
    super.initState();
    _body.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  /// Something to post: a status picked, and either words or a new
  /// status.
  bool get _canPost =>
      _status != null &&
      (_body.toMarkdown().trim().isNotEmpty ||
          _status != widget.project.status);

  void _post(StatusUpdatesScope scope) {
    final me = scope.me();
    final status = _status;
    if (me == null || status == null) return;
    scope.repo.post(
      project: widget.project,
      authorId: me,
      status: status,
      body: _body.toMarkdown(),
    );
    Navigator.pop(context);
  }

  /// The update shown on the right, by id; null for a new one (the form).
  String? _shown;

  /// Whether [_shown] has been set to start: it opens on the latest
  /// update (the form only when there's none yet).
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = StatusUpdatesScope.maybeOf(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: colors.card,
      shape: formShape,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: (size.width - 80).clamp(0, 920),
        height: (size.height - 80).clamp(0, 680),
        child: scope == null
            ? _layout(context, null, const [])
            : Watched<List<StatusUpdate>>(
                watch: () => scope.repo.watch(widget.project.id),
                current: () => scope.repo.forProject(widget.project.id),
                builder: (context, updates) => _layout(context, scope, updates),
              ),
      ),
    );
  }

  /// The header across the top; under it the updates at the left and, at
  /// the right, the one clicked or the form for a new one.
  Widget _layout(
    BuildContext context,
    StatusUpdatesScope? scope,
    List<StatusUpdate> updates,
  ) {
    final colors = context.colors;
    if (!_started) {
      _started = true;
      _shown = updates.firstOrNull?.id;
    }
    final shown = updates.where((u) => u.id == _shown).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, newEnabled: shown != null),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 340,
                child: ColoredBox(
                  // One color across the whole dialog: the card shade.
                  color: colors.card,
                  // A table like the list view's: column names, then
                  // one row per update.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: updates.isEmpty
                            ? const _NoUpdates()
                            : BottomFadeScrollView(
                                padding: const EdgeInsets.only(
                                  bottom: bottomFadeHeight,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final u in updates)
                                      _UpdateRow(
                                        update: u,
                                        selected: u.id == shown?.id,
                                        onTap: () =>
                                            setState(() => _shown = u.id),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              VerticalDivider(width: 1, thickness: 1, color: colors.cardBorder),
              Expanded(
                child: shown != null
                    ? _UpdateDetail(key: ValueKey(shown.id), update: shown)
                    : _form(scope),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Status of" the project, across the whole dialog with a line under
  /// it; at the right, New status (back to the form, kept as it was
  /// left) and close.
  Widget _header(BuildContext context, {required bool newEnabled}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 14, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.cardBorder)),
      ),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              'Status of ${widget.project.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: newEnabled ? () => setState(() => _shown = null) : null,
            icon: const Icon(Symbols.add, size: 18),
            label: const Text('New status'),
          ),
          // Closes without posting, like Cancel.
          IconButton(
            tooltip: 'Close',
            iconSize: 20,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              fixedSize: const Size.square(30),
              minimumSize: const Size.square(30),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => Navigator.pop(context),
            icon: Icon(Symbols.close, color: colors.text),
          ),
        ],
      ),
    );
  }

  /// A new update: its status, what's happening, then Cancel and Post.
  Widget _form(StatusUpdatesScope? scope) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        Row(
          spacing: 8,
          children: [
            for (final s in ProjectStatus.values)
              Expanded(
                child: _StatusOption(
                  status: s,
                  selected: s == _status,
                  onTap: () => setState(() => _status = s),
                ),
              ),
          ],
        ),
        // Fills the room left: as many lines as fit under the toolbar
        // (about 17px each at 13); a longer update scrolls.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => BottomFadeScrollView(
              child: RichTextEditor(
                controller: _body,
                fontSize: 13,
                minLines: ((box.maxHeight - 90) / 17.5).floor().clamp(3, 40),
                hintText: 'What\'s happening? Progress, risks, what\'s next…',
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: scope != null && _canPost ? () => _post(scope) : null,
              child: const Text('Post update'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// An update as one row of the table, like a task in the list view
/// ([TaskRow]): on the card shade, at least [TaskTable.height] tall, its
/// status at the left and the day it was posted at the right. A line under each; the row fills while hovered, and the one
/// shown at the right is outlined in the accent, like the task open in
/// the form. Clicking shows it there.
class _UpdateRow extends StatefulWidget {
  const _UpdateRow({
    required this.update,
    required this.selected,
    required this.onTap,
  });
  final StatusUpdate update;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_UpdateRow> createState() => _UpdateRowState();
}

class _UpdateRowState extends State<_UpdateRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final update = widget.update;
    final text = TextStyle(fontSize: 13.5, color: colors.text);
    return Semantics(
      button: true,
      selected: widget.selected,
      child: DecoratedBox(
        // On top, so the hover fill doesn't cover the lines.
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: widget.selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : Border(bottom: BorderSide(color: colors.cardBorder)),
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Material(
            color: _hover ? colors.rowHover : colors.card,
            child: InkWell(
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: 52,
                  ),
                  child: IntrinsicHeight(
                    // The status at the left, the day it was posted at
                    // the right.
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: update.status.color,
                        ),
                        Expanded(
                          child: Text(
                            update.status.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text,
                          ),
                        ),
                        Text(
                          postedOn(update),
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          style: text,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One update in full, at the dialog's right: its status, who posted it
/// and when (the full date), then everything they wrote. Scrolls.
class _UpdateDetail extends StatelessWidget {
  const _UpdateDetail({super.key, required this.update});
  final StatusUpdate update;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final author = scope?.find(update.authorId);
    final job = author?.jobTitle.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: BottomFadeScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, bottomFadeHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 18,
              children: [
                StatusLabel(update.status, fontSize: 18),
                Row(
                  spacing: 10,
                  children: [
                    if (author != null)
                      ProfileAvatar(
                        profile: author,
                        image: scope!.imageOf(author),
                        size: 32,
                      )
                    else
                      Icon(Symbols.person, size: 24, color: colors.mutedText),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            [
                              author?.displayName ?? 'Deleted profile',
                              if (job.isNotEmpty) job,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
                            ),
                          ),
                          // The day, then the time it was posted.
                          Text(
                            '${postedOn(update)}, ${postedAt(update)}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Divider(height: 1, thickness: 1, color: colors.cardBorder),
                if (update.body.trim().isEmpty)
                  Text(
                    'Nothing written with this update.',
                    style: TextStyle(fontSize: 13, color: colors.mutedText),
                  )
                else
                  RichTextView(markdown: update.body, fontSize: 14),
                // Under the post: its comments (the task form's, on the
                // update's id). The box to add one is pinned below.
                Divider(height: 1, thickness: 1, color: colors.cardBorder),
                TaskComments(taskId: update.id, fontSize: 13, showBox: false),
              ],
            ),
          ),
        ),
        // The box to write a comment, pinned at the bottom.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: TaskComments(taskId: update.id, fontSize: 13, showList: false),
        ),
      ],
    );
  }
}

/// A status to pick for the new update: a 36px box with its dot and
/// name; the picked one tinted with its color and outlined in it.
class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onTap,
  });
  final ProjectStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.alphaBlend(status.color.withValues(alpha: 0.2), colors.card)
            : colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: formRadius,
          side: BorderSide(color: selected ? status.color : colors.cardBorder),
        ),
        child: InkWell(
          customBorder: formShape,
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 8,
              children: [
                Icon(Icons.circle, size: 10, color: status.color),
                Flexible(
                  child: Text(
                    status.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: colors.text,
                    ),
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

class _NoUpdates extends StatelessWidget {
  const _NoUpdates();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Text(
      'No updates yet. The first one you post shows here, and on the '
      'project\'s dashboard.',
      style: TextStyle(fontSize: 13, color: context.colors.mutedText),
    ),
  );
}

/// The status as a small mark: its colored dot and name.
class StatusLabel extends StatelessWidget {
  const StatusLabel(this.status, {super.key, this.fontSize = 13});
  final ProjectStatus status;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 7,
    children: [
      Icon(Icons.circle, size: 10, color: status.color),
      Text(
        status.label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: context.colors.text,
        ),
      ),
    ],
  );
}

/// One status update: its status, who posted it and when, then what they
/// wrote. In the status dialog's list and on the dashboard.
class StatusUpdateView extends StatelessWidget {
  const StatusUpdateView({
    super.key,
    required this.update,
    this.fontSize = 13,
    this.showBody = true,
  });
  final StatusUpdate update;
  final double fontSize;

  /// False for just the status, author and time (the dialog's list).
  final bool showBody;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final author = scope?.find(update.authorId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        StatusLabel(update.status, fontSize: fontSize + 1),
        Row(
          spacing: 8,
          children: [
            if (author != null)
              ProfileAvatar(
                profile: author,
                image: scope!.imageOf(author),
                size: 20,
              )
            else
              Icon(Symbols.person, size: 18, color: colors.mutedText),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: author?.displayName ?? 'Deleted profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${postedOn(update)}',
                      style: TextStyle(color: colors.mutedText),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: fontSize - 0.5),
              ),
            ),
          ],
        ),
        if (showBody && update.body.trim().isNotEmpty)
          RichTextView(markdown: update.body, fontSize: fontSize),
      ],
    );
  }
}

/// The day [update] was posted, always as a date ("Nov 25"): no year, no
/// time, and never "Today".
String postedOn(StatusUpdate update) =>
    formatMonthDay(update.createdAt.toLocal());

/// The time of day [update] was posted: "4:00 PM".
String postedAt(StatusUpdate update) {
  final t = update.createdAt.toLocal();
  return formatTime(t.hour * 60 + t.minute);
}
