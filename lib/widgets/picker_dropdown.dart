import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../tasks/form_buttons.dart' show formFieldConstraints, formFieldHeight;

/// A row of chips with a box that drops down under it (the task form's
/// labels and its other projects): [builder] makes the row, with what
/// opens it (a + after the chips, or "Add …"); the box has a field at the
/// top ([hint]) and under it [list] for what's typed. ↑ ↓ move through
/// the [count] listed items; Enter calls [onSubmitted] with what's typed
/// and the highlighted item, if any. It stays open to add more; a click
/// outside it, Escape or the opener again closes it.
class PickerDropdown extends StatefulWidget {
  const PickerDropdown({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.count,
    required this.list,
    required this.onSubmitted,
    required this.builder,
    this.onChanged,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// How many items [list] shows for what's typed.
  final int Function(String text) count;

  /// The items under the field for what's typed, the highlighted one
  /// shaded; null when there are none.
  final Widget? Function(BuildContext context, String text, int? highlight)
  list;

  /// Enter: what's typed, and the item ↑ ↓ moved to (null if they weren't
  /// used).
  final void Function(String text, int? highlight) onSubmitted;

  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  /// The row the box opens under; its toggle opens (and, clicked again,
  /// closes) the box.
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  State<PickerDropdown> createState() => PickerDropdownState();
}

/// Reach it with a [GlobalKey] to [close] the box (after picking the one
/// thing a single choice takes).
class PickerDropdownState extends State<PickerDropdown> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  /// Clicks inside the box and on the row don't close it.
  final _region = Object();

  /// The listed item ↑ ↓ moved to; null until they're used.
  int? _highlight;

  String _lastText = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (widget.controller.text == _lastText) return;
    _lastText = widget.controller.text;
    setState(() => _highlight = null);
  }

  void _open() {
    setState(() => _highlight = null);
    _portal.show();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  /// Closes the box (if open), clearing what's typed.
  void close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    widget.focusNode.unfocus();
    widget.controller.clear();
  }

  void _toggle() => _portal.isShowing ? close() : _open();

  KeyEventResult _onKey(KeyEvent event, int count) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when count > 0:
        setState(() => _highlight = ((_highlight ?? -1) + 1) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when count > 0:
        setState(() => _highlight = ((_highlight ?? count) - 1) % count);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Closes the box only; the next Escape closes the form.
        close();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Widget _box(BuildContext context) {
    final text = widget.controller.text;
    final count = widget.count(text);
    final highlight = _highlight != null && _highlight! < count
        ? _highlight
        : null;
    final list = widget.list(context, text, highlight);
    final field = Focus(
      onKeyEvent: (_, event) => _onKey(event, count),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        inputFormatters: widget.inputFormatters,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: context.colors.placeholder),
          constraints: formFieldConstraints,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
          // No focus highlight: the same outline focused as not (the
          // usual outline color).
          focusedBorder: OutlineInputBorder(
            borderRadius: formRadius,
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        // Keeps focus after Enter, to add another.
        onEditingComplete: () {},
        onSubmitted: (text) {
          widget.onSubmitted(text, highlight);
          widget.focusNode.requestFocus();
        },
        onChanged: widget.onChanged,
      ),
    );
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: formRadius,
        side: BorderSide(color: context.colors.cardBorder),
      ),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(padding: const EdgeInsets.all(8), child: field),
            if (list != null) Flexible(child: list),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: _link,
    child: OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 4),
        child: Align(
          alignment: Alignment.topLeft,
          child: TapRegion(
            groupId: _region,
            onTapOutside: (_) => close(),
            // Clicks in the list keep the field focused.
            child: TextFieldTapRegion(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: _box(context),
              ),
            ),
          ),
        ),
      ),
      child: TapRegion(
        groupId: _region,
        child: widget.builder(context, _toggle),
      ),
    ),
  );
}

/// One item in a [PickerDropdown]'s list: shaded when [active] (↑ ↓), and
/// kept in view as it moves.
class PickerItem extends StatelessWidget {
  const PickerItem({
    super.key,
    required this.active,
    required this.onTap,
    required this.child,
  });
  final bool active;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Scrollable.ensureVisible(context, alignment: 0.5);
        }
      });
    }
    return InkWell(
      borderRadius: formRadius,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: active ? context.colors.hover : null,
          borderRadius: formRadius,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: child,
      ),
    );
  }
}

/// A [PickerDropdown]'s list: under the field, scrolling when long.
class PickerList extends StatelessWidget {
  const PickerList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
    shrinkWrap: true,
    itemCount: itemCount,
    itemBuilder: itemBuilder,
  );
}

/// What opens a [PickerDropdown] before there are chips: "Add …" in the
/// placeholder color, like an empty field's hint, brightening to the text
/// color while hovered (or focused). It's a field's height, its text in
/// the middle, so it lines up with the field's label.
class PickerAddText extends StatelessWidget {
  const PickerAddText(this.text, {super.key, required this.onPressed});
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      // A fixed height: the Mac's compact density would make the button
      // itself 8 shorter, putting the text above the label's middle.
      height: formFieldHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: TextButton(
          onPressed: onPressed,
          style:
              TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13),
              ).copyWith(
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                foregroundColor: WidgetStateProperty.resolveWith(
                  (states) =>
                      states.contains(WidgetState.hovered) ||
                          states.contains(WidgetState.focused)
                      ? colors.text
                      : colors.placeholder,
                ),
              ),
          child: Text(text),
        ),
      ),
    );
  }
}
