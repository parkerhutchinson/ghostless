import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../profiles/people_search.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../widgets/selected_text.dart';

/// One choice in the assignee search: a person, or Unassigned (null).
final class _Choice {
  const _Choice(this.profile);
  final Profile? profile;
}

/// Who a task is assigned to, as a search field: it shows the assignee
/// (their avatar and name, or Unassigned); click it and type to find
/// someone by name, job title or department, then pick them from the list
/// under it (or with ↑↓ and Enter). Escape or clicking away puts back the
/// assignee. Unassigned is offered first while nothing's been typed. The ✕
/// unassigns and starts a fresh search.
class AssigneeField extends StatefulWidget {
  const AssigneeField({
    super.key,
    required this.assigneeId,
    required this.onChanged,
    this.enabled = true,
    this.width,
    this.fontSize = 13,
  });

  final String? assigneeId;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  final double? width;
  final double fontSize;

  @override
  State<AssigneeField> createState() => _AssigneeFieldState();
}

class _AssigneeFieldState extends State<AssigneeField> {
  late final _text = AppTextController();
  final _focus = FocusNode();

  /// The list's widest: a little wider than the field, for job titles.
  static const _listWidth = 280.0;
  static const _listMaxHeight = 260.0;

  ProfilesScope? get _scope => ProfilesScope.maybeOf(context);
  Profile? get _assignee => _scope?.find(widget.assigneeId);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_focus.hasFocus) _showAssignee();
  }

  @override
  void didUpdateWidget(AssigneeField old) {
    super.didUpdateWidget(old);
    if (old.assigneeId != widget.assigneeId && !_focus.hasFocus) {
      _showAssignee();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// The field's text when not searching: the assignee's name (empty for
  /// Unassigned, which shows as the hint).
  String get _assigneeText => _assignee?.displayName ?? '';

  void _showAssignee() => _text.value = TextEditingValue(
    text: _assigneeText,
    selection: TextSelection.collapsed(offset: _assigneeText.length),
  );

  void _focusChanged() {
    if (_focus.hasFocus) {
      // Typing replaces the name: start a search.
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    } else {
      // Left without picking anyone: back to the assignee.
      _showAssignee();
    }
    setState(() {});
  }

  /// What's typed, or nothing while it's still the assignee's name (so
  /// clicking in lists everyone).
  String _query(String text) => text == _assigneeText ? '' : text;

  Iterable<_Choice> _options(TextEditingValue value) {
    final scope = _scope;
    if (scope == null) return const [];
    final query = _query(value.text);
    return [
      if (query.trim().isEmpty ||
          'unassigned'.startsWith(query.trim().toLowerCase()))
        const _Choice(null),
      for (final p in searchPeople(scope.profiles, query)) _Choice(p),
    ];
  }

  /// The ✕: unassigned, and an empty search box with everyone listed,
  /// to pick someone else (or click away and leave it unassigned).
  void _clear() {
    widget.onChanged(null);
    _text.clear();
    _focus.requestFocus();
    setState(() {});
  }

  void _picked(_Choice choice) {
    widget.onChanged(choice.profile?.id);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final assignee = _assignee;
    final style = TextStyle(fontSize: widget.fontSize, color: colors.text);
    final searching = _focus.hasFocus;
    return SizedBox(
      width: widget.width,
      child: RawAutocomplete<_Choice>(
        textEditingController: _text,
        focusNode: _focus,
        optionsBuilder: _options,
        displayStringForOption: (c) => c.profile?.displayName ?? '',
        onSelected: _picked,
        // Rebuilt as the text changes: the ✕ shows once something's typed.
        fieldViewBuilder: (context, controller, focus, onSubmitted) =>
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      focus.unfocus,
                },
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  enabled: widget.enabled,
                  // Never scrolls (or bounces) on its own: a swipe over it
                  // scrolls the form instead.
                  scrollPhysics: const NeverScrollableScrollPhysics(),
                  style: style,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: searching ? 'Search people' : 'Unassigned',
                    hintStyle: style.copyWith(
                      color: searching ? colors.placeholder : colors.mutedText,
                    ),
                    // As tall as the dropdown it replaced (36 on the Mac).
                    contentPadding: const EdgeInsets.fromLTRB(0, 12.5, 8, 12.5),
                    // The assignee's avatar (or the Unassigned icon); a
                    // magnifying glass while searching.
                    prefixIcon: Padding(
                      // The text field adds a few pixels of its own: 4
                      // here makes the gap to the name 8, as in the list.
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      // The assignee's avatar; an empty one (the same
                      // size) while searching or unassigned.
                      child: searching || assignee == null
                          ? const _EmptyAvatar(size: 18)
                          : ProfileAvatar(
                              profile: assignee,
                              image: _scope?.imageOf(assignee),
                              size: 18,
                            ),
                    ),
                    prefixIconConstraints: const BoxConstraints(),
                    // ✕: unassigns, and starts a fresh search. Only when
                    // there's something to clear.
                    suffixIcon:
                        widget.enabled &&
                            (assignee != null ||
                                (searching && controller.text.isNotEmpty))
                        // As far from the right edge as the avatar is from
                        // the left.
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4, right: 8),
                            child: IconButton(
                              tooltip: 'Clear',
                              onPressed: _clear,
                              iconSize: 14,
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                // The hover square hugs the ✕.
                                fixedSize: const Size.square(16),
                                minimumSize: const Size.square(16),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(
                                Symbols.close,
                                color: colors.mutedText,
                              ),
                            ),
                          )
                        : null,
                    suffixIconConstraints: const BoxConstraints(),
                    enabledBorder: colors.fieldBorder,
                    disabledBorder: colors.fieldBorder,
                    border: colors.fieldBorder,
                  ),
                  onSubmitted: (_) => onSubmitted(),
                ),
              ),
            ),
        // Wider than the field (the autocomplete holds it to the field's
        // width otherwise), so names and job titles fit.
        optionsViewBuilder: (context, onSelected, options) => OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _listWidth,
          maxWidth: _listWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              color: colors.surface,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: formRadius,
                side: BorderSide(color: colors.formBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: _listMaxHeight,
                  maxWidth: _listWidth,
                  minWidth: _listWidth,
                ),
                child: options.isEmpty
                    ? const SizedBox.shrink()
                    : _ChoiceList(
                        choices: options.toList(),
                        selectedId: widget.assigneeId,
                        fontSize: widget.fontSize,
                        onSelected: onSelected,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The matching people, scrolling past [_AssigneeFieldState._listMaxHeight]
/// (with a scrollbar), the keyboard's highlighted one kept in view.
class _ChoiceList extends StatefulWidget {
  const _ChoiceList({
    required this.choices,
    required this.selectedId,
    required this.fontSize,
    required this.onSelected,
  });
  final List<_Choice> choices;
  final String? selectedId;
  final double fontSize;
  final ValueChanged<_Choice> onSelected;

  @override
  State<_ChoiceList> createState() => _ChoiceListState();
}

class _ChoiceListState extends State<_ChoiceList> {
  final _scroll = ScrollController();
  static const _rowHeight = 36.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the highlighted row into view (↑↓ past the visible ones).
  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _rowHeight + 4;
    final view = _scroll.position.viewportDimension;
    final offset = _scroll.offset;
    if (top < offset) {
      _scroll.jumpTo(top - 4);
    } else if (top + _rowHeight > offset + view) {
      _scroll.jumpTo(top + _rowHeight - view + 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    final highlighted = AutocompleteHighlightedOption.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(highlighted));
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemExtent: _rowHeight,
          itemCount: widget.choices.length,
          itemBuilder: (context, i) {
            final p = widget.choices[i].profile;
            // Just the job title (the department is searchable, but
            // there's no room for both).
            final role = p?.jobTitle.trim() ?? '';
            final selected = p?.id == widget.selectedId;
            // The full style the name is drawn in (the app's font), so
            // it's measured as drawn.
            final nameStyle = DefaultTextStyle.of(context).style.merge(
              TextStyle(
                fontSize: widget.fontSize,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: p == null ? colors.mutedText : colors.text,
              ),
            );
            final roleStyle = TextStyle(
              fontSize: 10.5,
              color: colors.mutedText,
            );
            final name = p?.displayName ?? 'Unassigned';
            return InkWell(
              onTap: () => widget.onSelected(widget.choices[i]),
              child: Container(
                color: i == highlighted ? colors.hover : null,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // The name gets the room it needs (up to most of the
                    // row); the job title what's left, against the right
                    // edge.
                    const gap = 8.0, avatar = 18.0, check = 14.0;
                    final room =
                        constraints.maxWidth -
                        avatar -
                        gap -
                        (selected ? check + 4 : 0);
                    final nameWidth = math.min(
                      _textWidth(
                            name,
                            nameStyle,
                            textScaler: MediaQuery.textScalerOf(context),
                          ) +
                          1,
                      role.isEmpty ? room : room * 0.65,
                    );
                    final roleRoom = math.max(0.0, room - nameWidth - 12);
                    return Row(
                      children: [
                        if (p == null)
                          Icon(
                            Symbols.person_off,
                            size: avatar,
                            color: colors.mutedText,
                          )
                        else
                          ProfileAvatar(
                            profile: p,
                            image: scope?.imageOf(p),
                            size: avatar,
                          ),
                        const SizedBox(width: gap),
                        SizedBox(
                          width: nameWidth,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: nameStyle,
                          ),
                        ),
                        // The current assignee: bold, with a ✓.
                        if (selected) ...[
                          const SizedBox(width: 4),
                          Icon(Symbols.check, size: check, color: colors.text),
                        ],
                        const Spacer(),
                        if (role.isNotEmpty && roleRoom > 0)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: roleRoom),
                            child: Text(
                              role,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: roleStyle,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// How wide [text] is, on one line, in [style].
double _textWidth(
  String text,
  TextStyle style, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// A blank profile circle, as big as a [ProfileAvatar] of [size]: where
/// someone's avatar goes before anyone's picked.
class _EmptyAvatar extends StatelessWidget {
  const _EmptyAvatar({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: context.colors.divider,
      shape: BoxShape.circle,
    ),
    child: Icon(
      Symbols.person,
      size: size * 0.7,
      color: context.colors.mutedText,
    ),
  );
}
