import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../tasks/due_date.dart';
import '../tasks/form_buttons.dart';
import '../tasks/rich_text/rich_text_editor.dart';
import 'comment.dart';
import 'comments_scope.dart';
import '../widgets/pane_dialog.dart';
import '../widgets/watched.dart';

/// What a comment can be formatted with: paragraphs, bold and links.
const commentTools = {RichTextTool.bold, RichTextTool.link};

/// A task's comments in the task form (or a status update's, in the
/// status dialog: [taskId] is then the update's id), oldest first: each with its
/// author's photo, name and job title and when it was posted; then a box
/// to write one (bold and links only). Comments are posted straight away,
/// not with the form's Save. Nothing outside a [CommentsScope].
class TaskComments extends StatefulWidget {
  const TaskComments({
    super.key,
    required this.taskId,
    this.fontSize = 12,
    this.showList = true,
    this.showBox = true,
  });

  /// Off for just the box to write one (pinned below the list
  /// elsewhere, as in the status dialog); [showBox] off for just the list.
  final bool showList;
  final bool showBox;

  /// Null for a task not created yet: it can't have comments.
  final String? taskId;
  final double fontSize;

  @override
  State<TaskComments> createState() => _TaskCommentsState();
}

class _TaskCommentsState extends State<TaskComments> {
  var _draft = RichTextController.fromMarkdown('');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _draft.addListener(_draftChanged);
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _canPost = false;
  void _draftChanged() {
    final can = _draft.text.trim().isNotEmpty;
    if (can != _canPost) setState(() => _canPost = can);
  }

  void _post() {
    final scope = CommentsScope.maybeOf(context);
    final taskId = widget.taskId, me = scope?.me();
    if (scope == null || taskId == null || me == null || !_canPost) return;
    scope.repo.add(taskId: taskId, authorId: me, body: _draft.toMarkdown());
    // A fresh box for the next one, still focused.
    final old = _draft..removeListener(_draftChanged);
    setState(() {
      _draft = RichTextController.fromMarkdown('')..addListener(_draftChanged);
      _canPost = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _focus.requestFocus();
  }

  Future<void> _delete(Comment c) async {
    final repo = CommentsScope.maybeOf(context)?.repo;
    // Centered in the view pane, like everything opened from it.
    final ok = await showPaneDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('It will be removed for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: deleteButtonStyle(),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) repo?.delete(c.id);
  }

  @override
  Widget build(BuildContext context) {
    final scope = CommentsScope.maybeOf(context);
    final taskId = widget.taskId;
    final muted = TextStyle(
      fontSize: widget.fontSize,
      color: context.colors.mutedText,
    );
    if (scope == null) return const SizedBox.shrink();
    if (taskId == null) {
      return Text(
        'Comments can be added once the task is created.',
        style: muted,
      );
    }
    final me = scope.me();
    return Watched<List<Comment>>(
      key: ValueKey(taskId),
      watch: () => scope.repo.watch(taskId),
      current: () => scope.repo.forTask(taskId),
      builder: (context, comments) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            if (widget.showList)
              for (final c in comments)
                _CommentView(
                  comment: c,
                  fontSize: widget.fontSize,
                  onDelete: c.authorId == me ? () => _delete(c) : null,
                ),
            // Writing one: the description's editor (bold and links
            // only), its toolbar, the text and the Comment button all in
            // one box, outlined in the accent while typing.
            if (widget.showBox)
              ListenableBuilder(
                listenable: _focus,
                // A little more room above it than between comments.
                builder: (context, child) => Padding(
                  padding: EdgeInsets.only(
                    top: comments.isEmpty || !widget.showList ? 0 : 16,
                  ),
                  child: DecoratedBox(
                    // Over the contents, so the thicker focused line doesn't
                    // move them.
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: formRadius,
                      border: Border.all(
                        color: _focus.hasFocus
                            ? Theme.of(context).colorScheme.primary
                            : context.colors.formBorder,
                        width: _focus.hasFocus ? 2 : 1,
                      ),
                    ),
                    child: child,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RichTextEditor(
                      controller: _draft,
                      focusNode: _focus,
                      fontSize: widget.fontSize,
                      minLines: 2,
                      hintText: 'Write a comment',
                      tools: commentTools,
                      onSubmit: _post,
                      bordered: false,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                      child: Row(
                        children: [
                          Text('⌘Return to post', style: muted),
                          const Spacer(),
                          FilledButton(
                            style: formButtonStyle,
                            onPressed: _canPost && me != null ? _post : null,
                            child: const Text('Comment'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One comment: its author's photo, name and job title, when it was
/// posted, and what it says. The author can delete it.
class _CommentView extends StatelessWidget {
  const _CommentView({
    required this.comment,
    required this.fontSize,
    this.onDelete,
  });
  final Comment comment;
  final double fontSize;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final Profile? author = scope?.find(comment.authorId);
    final job = author?.jobTitle.trim() ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        if (author != null)
          ProfileAvatar(
            profile: author,
            image: scope!.imageOf(author),
            size: 28,
          )
        else
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colors.divider,
              shape: BoxShape.circle,
            ),
            child: Icon(Symbols.person, size: 18, color: colors.mutedText),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Row(
                children: [
                  // Name, job title and time take the room left of the
                  // delete button.
                  Expanded(
                    child: Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text:
                                      author?.displayName ?? 'Deleted profile',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: colors.text,
                                  ),
                                ),
                                if (job.isNotEmpty)
                                  TextSpan(
                                    text: '  $job',
                                    style: TextStyle(color: colors.mutedText),
                                  ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: fontSize + 0.5),
                          ),
                        ),
                        Text(
                          '· ${commentTime(comment.createdAt.toLocal(), DateTime.now())}',
                          style: TextStyle(
                            fontSize: fontSize - 0.5,
                            color: colors.mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onDelete case final delete?)
                    IconButton(
                      tooltip: 'Delete comment',
                      onPressed: delete,
                      iconSize: 14,
                      padding: EdgeInsets.zero,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(20),
                        minimumSize: const Size.square(20),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: Icon(Symbols.delete, color: colors.mutedText),
                    ),
                ],
              ),
              RichTextView(markdown: comment.body, fontSize: fontSize),
            ],
          ),
        ),
      ],
    );
  }
}

/// When a comment was posted: "Today, 3:42 PM", "Yesterday, 9:05 AM", or
/// "Nov 17, 2026, 3:42 PM".
String commentTime(DateTime when, DateTime now) {
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final time = formatTime(when.hour * 60 + when.minute);
  return switch (today.difference(day).inDays) {
    0 => 'Today, $time',
    1 => 'Yesterday, $time',
    _ => '${formatDate(day)}, $time',
  };
}
