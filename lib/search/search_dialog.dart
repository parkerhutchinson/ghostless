import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_logo.dart';
import '../tasks/task.dart';
import '../tasks/due_date.dart';
import '../tasks/label_line.dart';
import '../tasks/task_repository.dart';
import 'task_search.dart';
import '../widgets/selected_text.dart';

/// Search (⌘K, or the magnifying glass): finds tasks in [projects] by
/// title, label or assignee (one at a time, picked by the toggle under
/// the field) as you type. ↑ ↓ pick one, Enter (or a click)
/// calls [onOpen] with it and the board it opens on; Escape closes.
/// Centered in the pane right of [paneLeft] (the sidebar).
Future<void> showSearchDialog(
  BuildContext context, {
  required TaskRepository tasks,
  required List<Project> projects,
  required void Function(Task task, String projectId) onOpen,
  double paneLeft = 0,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _SearchDialog(
    tasks: tasks,
    projects: projects,
    onOpen: onOpen,
    paneLeft: paneLeft,
  ),
);

class _SearchDialog extends StatefulWidget {
  const _SearchDialog({
    required this.tasks,
    required this.projects,
    required this.onOpen,
    required this.paneLeft,
  });

  /// Where the main pane starts (right of the sidebar): it's centered in
  /// the pane, not the window.
  final double paneLeft;

  final TaskRepository tasks;
  final List<Project> projects;
  final void Function(Task task, String projectId) onOpen;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  static const _width = 600.0;

  /// A result: its two lines (the title, 14; then project and labels,
  /// [_labelLineHeight]; 5 apart), with 13px above and below.
  static const _rowPadding = 13.0;
  static const _rowHeight = 14 + 5 + _labelLineHeight + 2 * _rowPadding;

  static const _maxListHeight = _rowHeight * 7;

  final _query = AppTextController();

  /// The field keeps the focus, even after a click on the toggle.
  final _queryFocus = FocusNode();
  final _scroll = ScrollController();

  /// Every task, read once when it opens.
  late final List<Task> _all = widget.tasks.current();

  List<SearchHit> _hits = const [];

  /// What to search in (the toggle under the field): titles to start.
  SearchField _field = SearchField.title;

  /// The highlighted result (↑ ↓, or the pointer).
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_search);
  }

  @override
  void dispose() {
    _query.dispose();
    _queryFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _search() {
    final scope = ProfilesScope.maybeOf(context);
    setState(() {
      _hits = searchTasks(
        _query.text,
        _all,
        widget.projects,
        assigneeNames: {
          for (final p in scope?.profiles ?? const []) p.id: p.displayName,
        },
        only: _field,
        firstWeekday: switch (MaterialLocalizations.of(context)
            .firstDayOfWeekIndex) {
          0 => DateTime.sunday,
          final i => i,
        },
      );
      _index = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _open(SearchHit hit) {
    Navigator.pop(context);
    widget.onOpen(hit.task, hit.project.id);
  }

  /// Moves the highlight by [by], keeping it in view.
  void _move(int by) {
    if (_hits.isEmpty) return;
    setState(() => _index = (_index + by).clamp(0, _hits.length - 1));
    if (!_scroll.hasClients) return;
    final top = _index * _rowHeight;
    final view = _scroll.position.viewportDimension;
    // Kept clear of the fade at the bottom.
    final fade = _overflows ? _fadeHeight : 0.0;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + _rowHeight > _scroll.offset + view - fade) {
      _scroll.jumpTo(
        (top + _rowHeight - view + fade).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        ),
      );
    }
  }

  /// How far down the window the box sits.
  static const _topFraction = 0.34;

  /// The most the results can show: [_maxListHeight], or less in a
  /// short window, so they end above its bottom.
  double _listMax = _maxListHeight;

  @override
  Widget build(BuildContext context) {
    final words = searchWords(_query.text);
    final window = MediaQuery.sizeOf(context).height;
    final top = window * _topFraction;
    final muted = TextStyle(fontSize: 13, color: context.colors.mutedText);
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          // A share of the window's height, so it moves as that changes.
          top: top,
          left: widget.paneLeft + 24,
          right: 24,
        ),
        child: ConstrainedBox(
          // Room down to the window's bottom, less a margin.
          constraints: BoxConstraints(
            maxWidth: _width,
            maxHeight: (window - top - 24).clamp(0, double.infinity),
          ),
          child: Material(
            color: context.colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: formRadius,
              side: BorderSide(color: context.colors.formBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    _move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    _move(-1),
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _input(context),
                  if (words.isNotEmpty) ...[
                    Divider(height: 1, color: context.colors.formBorder),
                    if (_hits.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Text('No tasks match.', style: muted),
                      )
                    else
                      Flexible(
                        child: LayoutBuilder(
                          builder: (context, space) {
                            _listMax = space.maxHeight < _maxListHeight
                                ? space.maxHeight
                                : _maxListHeight;
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: _listMax),
                              child: _bottomFade(
                                ListView.builder(
                                  controller: _scroll,
                                  shrinkWrap: true,
                                  // Room below the last row to scroll it out
                                  // of the fade.
                                  padding: EdgeInsets.only(
                                    bottom: _overflows ? _fadeHeight : 0,
                                  ),
                                  itemExtent: _rowHeight,
                                  itemCount: _hits.length,
                                  itemBuilder: (context, i) => _ResultRow(
                                    hit: _hits[i],
                                    // By date: no words to pick out of titles.
                                    words: _field == SearchField.date
                                        ? const []
                                        : words,
                                    highlighted: i == _index,
                                    onHover: () => setState(() => _index = i),
                                    onTap: () => _open(_hits[i]),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// More results than fit: they fade out at the bottom.
  bool get _overflows => _hits.length * _rowHeight > _listMax;

  /// The results fade out at the bottom when there are more than fit. The
  /// fade stays put; padding below the last row lets it scroll clear.
  Widget _bottomFade(Widget list) {
    if (!_overflows) return list;
    // The scrollbar outside the fade, so it doesn't fade with the rows
    // (the list's own is turned off).
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _scroll,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 1 - _fadeHeight / bounds.height, 1],
          ).createShader(bounds),
          child: list,
        ),
      ),
    );
  }

  static const _fadeHeight = 48.0;

  static const _fields = {
    SearchField.title: ('Title', Symbols.title),
    SearchField.label: ('Label', Symbols.label),
    SearchField.assignee: ('Person', Symbols.person),
    SearchField.date: ('Date', Symbols.event),
  };

  /// Title, Label, Person or Date: what the words are looked for in. A small
  /// drop-down at the field's right.
  Widget _fieldMenu(BuildContext context) {
    final (label, icon) = _fields[_field]!;
    final style = TextStyle(fontSize: 12.5, color: context.colors.text);
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<SearchField>(
      tooltip: 'Search in',
      initialValue: _field,
      position: PopupMenuPosition.under,
      color: context.colors.surface,
      onSelected: (f) {
        _field = f;
        _search();
        _queryFocus.requestFocus();
      },
      // Back to typing either way (opening the menu took the focus).
      onCanceled: _queryFocus.requestFocus,
      itemBuilder: (_) => [
        for (final MapEntry(key: f, value: (text, icon)) in _fields.entries)
          PopupMenuItem(
            value: f,
            height: 34,
            child: Row(
              spacing: 8,
              children: [
                Icon(icon, size: 16, color: context.colors.text),
                Text(text, style: style),
              ],
            ),
          ),
      ],
      // The current choice as an accent button: the accent fill, dark
      // text (colorScheme.onPrimary).
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: formRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            Icon(icon, size: 15, color: scheme.onPrimary),
            Text(label, style: style.copyWith(color: scheme.onPrimary)),
            Icon(Symbols.expand_more, size: 16, color: scheme.onPrimary),
          ],
        ),
      ),
    );
  }

  Widget _input(BuildContext context) => Padding(
    // Left as much as the text has above and below (the field's 24).
    padding: const EdgeInsets.only(left: 24, right: 16),
    child: Row(
      spacing: 10,
      children: [
        Expanded(
          child: TextField(
            controller: _query,
            focusNode: _queryFocus,
            autofocus: true,
            style: TextStyle(fontSize: 15, color: context.colors.text),
            textInputAction: TextInputAction.go,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 24),
              hintText: switch (_field) {
                SearchField.title => 'Search task titles',
                SearchField.label => 'Search labels',
                SearchField.assignee => 'Search by person',
                SearchField.date => 'Due date: today, next week, Nov 20…',
              },
              hintStyle: TextStyle(color: context.colors.placeholder),
            ),
            onSubmitted: (_) {
              if (_index < _hits.length) _open(_hits[_index]);
            },
          ),
        ),
        _fieldMenu(context),
      ],
    ),
  );
}

/// One result: its title, then its project, column
/// (and due date, searching by date) and labels; its assignee's avatar
/// at the right.
/// A label chip's height: a result's second line.
const _labelLineHeight = 20.0;

/// How wide a result's title gets before it's cut short.
const _maxTitleWidth = 400.0;

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.hit,
    required this.words,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final SearchHit hit;
  final List<String> words;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final task = hit.task;
    final muted = TextStyle(fontSize: 12, color: context.colors.mutedText);
    final titleStyle = TextStyle(
      fontSize: 14,
      // A line box as tall as the letters (no extra space above them), so
      // the two lines sit centered in the row.
      height: 1,
      leadingDistribution: TextLeadingDistribution.even,
      color: hit.completed ? context.colors.mutedText : context.colors.text,
      decoration: hit.completed ? TextDecoration.lineThrough : null,
      decorationColor: context.colors.text,
    );
    // Labels that matched first, then the rest.
    final labels = [
      ...task.tags.where((l) => words.any(l.toLowerCase().contains)),
      ...task.tags.where((l) => !words.any(l.toLowerCase().contains)),
    ];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          // A line under every row, drawn over it (not taking room from
          // the centered lines).
          foregroundDecoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.colors.cardBorder),
            ),
          ),
          color: highlighted ? context.colors.hover : null,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 5,
                  children: [
                    // Cut short ("…") well before the avatar.
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxTitleWidth,
                      ),
                      child: Text(
                        task.title,
                        style: titleStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // A label chip's height, labels or not: every row's
                    // lines take the same room.
                    SizedBox(
                      height: _labelLineHeight,
                      child: Row(
                        spacing: 6,
                        children: [
                          ProjectIcon(project: hit.project, size: 12),
                          Flexible(
                            child: Text(
                              [
                                hit.project.name,
                                hit.column.title,
                                // By date: the day it's due.
                                if (hit.fields.contains(SearchField.date))
                                  formatDate(task.dueDate!),
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ),
                          // As many as fit on the line, then "+N".
                          if (labels.isNotEmpty)
                            Flexible(
                              child: LabelLine(
                                tags: labels,
                                projectId: task.originId,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Nobody (or a profile that's gone): the empty picture.
              if (ProfilesScope.maybeOf(context)?.find(task.assigneeId) == null)
                const Tooltip(
                  message: 'Unassigned',
                  child: UnassignedAvatar(size: 22),
                )
              else
                AssigneeAvatar(assigneeId: task.assigneeId, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
