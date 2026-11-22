import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import 'due_date.dart';

/// Faded white, like the form's placeholders.

/// Due date (a box you can type in, with a calendar underneath), optional
/// time (half-hour list, or typed), and a button to clear both.
class DueDateField extends StatelessWidget {
  const DueDateField({
    super.key,
    required this.date,
    required this.time,
    required this.onChanged,
  });

  final DateTime? date;
  final int? time;

  /// Called with the new day and time; (null, null) clears the due date.
  final void Function(DateTime? date, int? time) onChanged;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return Row(
      spacing: 8,
      children: [
        SizedBox(
          width: 170,
          child: _DateField(
            date: date,
            // Emptying the box removes the due date, time included.
            onChanged: (d) => onChanged(d, d == null ? null : time),
          ),
        ),
        if (date != null) ...[
          SizedBox(
            width: 140,
            child: _TimeField(time: time, onChanged: (t) => onChanged(date, t)),
          ),
          IconButton(
            tooltip: 'Remove due date',
            onPressed: () => onChanged(null, null),
            style: IconButton.styleFrom(shape: formShape),
            icon: Icon(Symbols.close, size: 18),
          ),
        ],
      ],
    );
  }
}

/// Size of the dropdown calendar: a 36px header, a 20px weekday row and
/// 6 weeks of 30px rows, 7 columns of 34px, with 8px padding all round.
const _dayWidth = 34.0, _dayHeight = 30.0;
const _calendarWidth = 7 * _dayWidth + 16;
const _calendarHeight = 36 + 20 + 6 * _dayHeight + 16;

/// Text size in the date and time boxes: the same as the form's tag and
/// project chips.
const _fieldFontSize = 12.5;

/// Shared look of the date and time boxes.
InputDecoration _boxDecoration(
  BuildContext context,
  String hint,
  IconData icon,
) => InputDecoration(
  isDense: true,
  hintText: hint,
  hintStyle: TextStyle(
    fontSize: _fieldFontSize,
    color: context.colors.placeholder,
  ),
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
  enabledBorder: context.colors.fieldBorder,
  border: context.colors.fieldBorder,
  suffixIcon: Icon(icon, size: 16, color: context.colors.text),
  suffixIconConstraints: const BoxConstraints(minWidth: 32),
);

/// A date box: click it for a calendar underneath, or type ("nov 20",
/// "11/20", "tomorrow"); it's read on Enter or when leaving the box. Empty
/// means no due date.
class _DateField extends StatefulWidget {
  const _DateField({required this.date, required this.onChanged});
  final DateTime? date;
  final ValueChanged<DateTime?> onChanged;

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late final _controller = TextEditingController(text: _label(widget.date))
    ..addListener(_onTyped);
  final _focus = FocusNode();
  final _calendar = OverlayPortalController();

  /// The day the calendar shows: what's typed so far, if it's a date.
  DateTime? _preview;

  static String _label(DateTime? d) => d == null ? '' : formatDate(d);

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _calendar.show();
      } else {
        _calendar.hide();
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(_DateField old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date && !_focus.hasFocus) {
      _controller.text = _label(widget.date);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Moves the calendar to the date being typed.
  void _onTyped() {
    final parsed = parseDate(_controller.text, _today);
    if (parsed != null && parsed != _preview) setState(() => _preview = parsed);
  }

  /// Reads what was typed: a date, nothing (no due date), or back to the
  /// previous date if it isn't one.
  void _commit() {
    final text = _controller.text.trim();
    if (text == _label(widget.date)) return;
    final date = text.isEmpty ? null : parseDate(text, _today);
    if (date == null && text.isNotEmpty) {
      _controller.text = _label(widget.date);
      return;
    }
    _controller.text = _label(date);
    _preview = date; // an emptied box opens on today next time
    if (date != widget.date) widget.onChanged(date);
  }

  void _pick(DateTime day) {
    _controller.text = _label(day);
    widget.onChanged(day);
    _calendar.hide();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _preview ?? widget.date ?? _today;
    // Placed from the box's position during layout (not with a
    // CompositedTransformFollower, which breaks the calendar's tooltips).
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _calendar,
      overlayChildBuilder: (context, info) {
        final box = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        // Below the box, or above it if there isn't room.
        final below = box.bottom + 4;
        final top = below + _calendarHeight <= info.overlaySize.height
            ? below
            : box.top - 4 - _calendarHeight;
        return Positioned(
          left: box.left,
          top: top,
          width: _calendarWidth,
          // Clicks in the calendar don't count as leaving the box.
          child: TextFieldTapRegion(
            child: Material(
              color: context.colors.surface,
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: formRadius,
                side: BorderSide(color: context.colors.formBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: _calendarHeight,
                child: _MonthCalendar(
                  // Rebuilt when a typed date moves it to another month.
                  key: ValueKey(shown),
                  initialMonth: shown,
                  selected: widget.date,
                  onPicked: _pick,
                ),
              ),
            ),
          ),
        );
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            _calendar.hide();
          },
        },
        child: TextField(
          // Never scrolls (or bounces) on its own: a swipe over it
          // scrolls the form instead.
          scrollPhysics: const NeverScrollableScrollPhysics(),
          controller: _controller,
          focusNode: _focus,
          style: const TextStyle(fontSize: _fieldFontSize),
          onTap: _calendar.show,
          onSubmitted: (_) {
            _commit();
            _calendar.hide();
          },
          decoration: _boxDecoration(
            context,
            'Add due date',
            Symbols.calendar_today,
          ),
        ),
      ),
    );
  }
}

/// A time box: click it for every half hour, or type ("2:30p", "1430")
/// and the best match is filled in on Enter or when leaving the box. Empty
/// means no time.
class _TimeField extends StatefulWidget {
  const _TimeField({required this.time, required this.onChanged});
  final int? time;
  final ValueChanged<int?> onChanged;

  @override
  State<_TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<_TimeField> {
  late final _controller = TextEditingController(text: _label(widget.time));
  final _focus = FocusNode();

  /// The option last scrolled into view, so it's only done when the
  /// highlight moves (not every time the row is rebuilt while scrolling).
  int? _scrolledTo;

  static String _label(int? time) => time == null ? '' : formatTime(time);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(_TimeField old) {
    super.didUpdateWidget(old);
    if (old.time != widget.time && !_focus.hasFocus) {
      _controller.text = _label(widget.time);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Fills in what was typed: the best match, nothing (no time) for an
  /// empty box, or back to the previous time if it isn't a time.
  void _commit() {
    final text = _controller.text.trim();
    if (text == _label(widget.time)) return;
    final time = text.isEmpty ? null : parseTime(text);
    if (time == null && text.isNotEmpty) {
      _controller.text = _label(widget.time);
      return;
    }
    _controller.text = _label(time);
    widget.onChanged(time);
  }

  /// While the box shows the chosen time, the list starts there (so it's
  /// highlighted) and runs through the day; otherwise it's what matches.
  Iterable<int> _options(TextEditingValue value) {
    _scrolledTo = null;
    final current = widget.time;
    if (value.text.isEmpty || value.text == _label(current)) {
      if (current == null) return timeSlots;
      final start = timeSlots.indexWhere((s) => s >= current);
      return [
        if (!timeSlots.contains(current)) current,
        ...timeSlots.skip(start < 0 ? 0 : start),
        ...timeSlots.take(start < 0 ? 0 : start),
      ];
    }
    return timeSuggestions(value.text);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<int>(
      textEditingController: _controller,
      focusNode: _focus,
      optionsBuilder: _options,
      displayStringForOption: formatTime,
      onSelected: (t) {
        _controller.text = formatTime(t);
        widget.onChanged(t);
      },
      fieldViewBuilder: (context, controller, focus, onSubmitted) => TextField(
        // Never scrolls (or bounces) on its own: a swipe over it
        // scrolls the form instead.
        scrollPhysics: const NeverScrollableScrollPhysics(),
        controller: controller,
        focusNode: focus,
        style: const TextStyle(fontSize: _fieldFontSize),
        onSubmitted: (_) {
          onSubmitted();
          _commit();
        },
        decoration: _boxDecoration(context, 'Any time', Symbols.schedule),
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: context.colors.surface,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: formRadius,
            side: BorderSide(color: context.colors.formBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 140),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, i) {
                final option = options.elementAt(i);
                final highlighted =
                    AutocompleteHighlightedOption.of(context) == i;
                if (highlighted && _scrolledTo != i) {
                  _scrolledTo = i;
                  // Keep the highlighted time in view (arrow keys, or the
                  // current time opening at the top).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (context.mounted) {
                      Scrollable.ensureVisible(context, alignment: 0.5);
                    }
                  });
                }
                return InkWell(
                  onTap: () => onSelected(option),
                  child: Container(
                    color: highlighted
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      formatTime(option),
                      style: highlighted
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                            )
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A month of days: always 6 weeks, with the neighbouring months' days
/// (faded) filling the first and last rows. Arrows change the month;
/// clicking any day picks it.
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({
    super.key,
    required this.initialMonth,
    required this.selected,
    required this.onPicked,
  });

  final DateTime initialMonth;
  final DateTime? selected;
  final ValueChanged<DateTime> onPicked;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late DateTime _month = DateTime(
    widget.initialMonth.year,
    widget.initialMonth.month,
  );

  void _shift(int months) =>
      setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final l = MaterialLocalizations.of(context);
    // firstDayOfWeekIndex: 0 = Sunday … 6 = Saturday.
    final firstIndex = l.firstDayOfWeekIndex;
    final firstWeekday = firstIndex == 0 ? DateTime.sunday : firstIndex;
    final days = calendarDays(_month, firstWeekday: firstWeekday);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Widget arrow(String tooltip, IconData icon, int months) => SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        iconSize: 18,
        style: IconButton.styleFrom(shape: formShape),
        onPressed: () => _shift(months),
        icon: Icon(icon),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l.formatMonthYear(_month),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                arrow(l.previousMonthTooltip, Symbols.chevron_left, -1),
                arrow(l.nextMonthTooltip, Symbols.chevron_right, 1),
              ],
            ),
          ),
          SizedBox(
            height: 20,
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  SizedBox(
                    width: _dayWidth,
                    child: Center(
                      child: Text(
                        l.narrowWeekdays[(firstIndex + i) % 7],
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.mutedText,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (final day in days.skip(week * 7).take(7))
                  _Day(
                    day: day,
                    inMonth: day.month == _month.month,
                    isToday: day == today,
                    isSelected: day == widget.selected,
                    onTap: () => widget.onPicked(day),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;

  /// False for the neighbouring months' days, which are faded.
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _dayWidth,
      height: _dayHeight,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: formRadius,
            side: isToday && !isSelected
                ? BorderSide(color: context.colors.mutedText)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: formShape,
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected
                      ? Theme.of(context).colorScheme.onPrimary
                      : inMonth
                      ? null
                      : context.colors.placeholder,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
