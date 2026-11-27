import 'dart:math' as math;

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../profiles/people_search.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../profiles/profiles_scope.dart';
import '../widgets/selected_text.dart';
import '../widgets/picker_dropdown.dart';
import 'form_buttons.dart' show formFieldHeight;

/// Who a task is assigned to, like the form's other projects: the
/// assignee as a chip (their avatar and name; ✕ unassigns), or "Add
/// assignee" when there's no one. Either opens a box (a [PickerDropdown])
/// with a field at the top to find someone by name, job title or
/// department, and the matching people under it: click one, or ↑ ↓ then
/// Enter (Enter alone picks the first). Picking someone closes the box.
class AssigneeField extends StatefulWidget {
  const AssigneeField({
    super.key,
    required this.assigneeId,
    required this.onChanged,
    this.enabled = true,
    this.fontSize = 13,
  });

  final String? assigneeId;
  final ValueChanged<String?> onChanged;

  /// False: just the assignee, which can't be changed.
  final bool enabled;
  final double fontSize;

  /// The chip's height: the same as the form's fields and its project and
  /// label chips.
  static const chipHeight = formFieldHeight;

  @override
  State<AssigneeField> createState() => _AssigneeFieldState();
}

class _AssigneeFieldState extends State<AssigneeField> {
  final _text = AppTextController();
  final _focus = FocusNode();
  final _dropdown = GlobalKey<PickerDropdownState>();

  ProfilesScope? get _scope => ProfilesScope.maybeOf(context);
  Profile? get _assignee => _scope?.find(widget.assigneeId);

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  List<Profile> _matches(String text) {
    final scope = _scope;
    return scope == null ? const [] : searchPeople(scope.profiles, text);
  }

  void _pick(Profile p) {
    widget.onChanged(p.id);
    _dropdown.currentState?.close();
  }

  /// The assignee: avatar and name; clicking it opens the box to pick
  /// someone else, the ✕ unassigns.
  Widget _chip(Profile p, VoidCallback toggle) {
    final colors = context.colors;
    return SizedBox(
      height: AssigneeField.chipHeight,
      child: InputChip(
        // The Mac's compact density would draw it shorter than the fields.
        visualDensity: VisualDensity.standard,
        label: Text(
          p.displayName,
          style: TextStyle(fontSize: widget.fontSize, color: colors.text),
        ),
        avatar: ProfileAvatar(profile: p, image: _scope?.imageOf(p), size: 18),
        backgroundColor: colors.card,
        side: BorderSide(color: colors.formBorder),
        tooltip: widget.enabled ? 'Change assignee' : null,
        onPressed: widget.enabled ? toggle : null,
        deleteIcon: Icon(Symbols.close, size: 14, color: colors.text),
        // An empty message means no tooltip on the ✕.
        deleteButtonTooltipMessage: '',
        onDeleted: widget.enabled ? () => widget.onChanged(null) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PickerDropdown(
    key: _dropdown,
    controller: _text,
    focusNode: _focus,
    hint: 'Search people',
    count: (text) => _matches(text).length,
    list: (context, text, highlight) {
      final people = _matches(text);
      if (people.isEmpty) return null;
      return PickerList(
        itemCount: people.length,
        itemBuilder: (context, i) => PickerItem(
          active: i == highlight,
          onTap: () => _pick(people[i]),
          child: _PersonRow(
            profile: people[i],
            selected: people[i].id == widget.assigneeId,
            fontSize: widget.fontSize,
          ),
        ),
      );
    },
    onSubmitted: (text, highlight) {
      final people = _matches(text);
      if (people.isNotEmpty) _pick(people[highlight ?? 0]);
    },
    builder: (context, toggle) {
      final assignee = _assignee;
      if (assignee != null) return _chip(assignee, toggle);
      if (!widget.enabled) {
        return SizedBox(
          // As tall as a field, so it lines up with the field's label.
          height: formFieldHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              'Unassigned',
              style: TextStyle(
                fontSize: widget.fontSize,
                color: context.colors.mutedText,
              ),
            ),
          ),
        );
      }
      return PickerAddText('Add assignee', onPressed: toggle);
    },
  );
}

/// A person in the box: avatar, name (with a ✓, not bold, when they're
/// the assignee) and, against the right edge, their job title.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.profile,
    required this.selected,
    required this.fontSize,
  });
  final Profile profile;
  final bool selected;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scope = ProfilesScope.maybeOf(context);
    // Just the job title (the department is searchable, but there's no
    // room for both).
    final role = profile.jobTitle.trim();
    // The full style the name is drawn in (the app's font), so it's
    // measured as drawn.
    final nameStyle = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        color: colors.text,
      ),
    );
    final name = profile.displayName;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The name gets the room it needs (up to most of the row); the job
        // title what's left, against the right edge.
        const gap = 8.0, avatar = 18.0, check = 14.0;
        final room =
            constraints.maxWidth - avatar - gap - (selected ? check + 4 : 0);
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
            ProfileAvatar(
              profile: profile,
              image: scope?.imageOf(profile),
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
                  style: TextStyle(fontSize: 10.5, color: colors.mutedText),
                ),
              ),
          ],
        );
      },
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
