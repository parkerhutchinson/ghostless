import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_theme.dart';
import 'rich_text_model.dart';

/// A text field's controller that also holds bold, italic, links and
/// lists (see [RichTextModel]), draws them, and keeps them in place as the
/// text is edited. Read it out with [toMarkdown].
class RichTextController extends TextEditingController {
  RichTextController.fromMarkdown(String markdown)
    : this._(RichTextModel.fromMarkdown(markdown));

  RichTextController._(this._model) : super(text: _model.text);

  final RichTextModel _model;

  /// The bold/italic the next typed text gets; null to take it from the
  /// text before the cursor. Set by B and I with nothing selected.
  Set<MarkType>? _typing;

  String toMarkdown() => _model.toMarkdown();

  Set<MarkType> get _typingStyles {
    final s = selection;
    if (!s.isValid) return const {};
    return _typing ??= s.isCollapsed
        ? _model.stylesAt(s.start)
        : _model.stylesAt(s.start + 1);
  }

  @override
  set value(TextEditingValue next) {
    final old = super.value;
    if (next.text == old.text) {
      if (next.selection != old.selection) _typing = null;
      super.value = next;
      return;
    }
    // What changed: the text between the common start and end.
    final a = old.text, b = next.text;
    var start = 0;
    while (start < a.length &&
        start < b.length &&
        a.codeUnitAt(start) == b.codeUnitAt(start)) {
      start++;
    }
    var end = 0;
    while (end < a.length - start &&
        end < b.length - start &&
        a.codeUnitAt(a.length - 1 - end) == b.codeUnitAt(b.length - 1 - end)) {
      end++;
    }
    final removedEnd = a.length - end;
    final inserted = b.substring(start, b.length - end);

    // Backspace just after a list prefix takes the prefix off.
    final prefix =
        inserted.isEmpty &&
            removedEnd == start + 1 &&
            old.selection.isCollapsed &&
            old.selection.start == removedEnd
        ? _model.prefixBefore(removedEnd)
        : null;
    if (prefix != null) {
      _model
        ..tracked = [removedEnd, removedEnd]
        ..replace(prefix.$1, prefix.$2, '')
        ..renumber();
    } else {
      _model.replace(start, removedEnd, inserted, style: _typingStyles);
      _model.tracked = [next.selection.baseOffset, next.selection.extentOffset];
      if (inserted == '\n') _model.afterNewline(start);
      _model.renumber();
    }
    final changed = _model.text != b;
    final [base, extent] = _model.tracked;
    super.value = TextEditingValue(
      text: _model.text,
      selection: changed
          ? TextSelection(baseOffset: base, extentOffset: extent)
          : next.selection,
      composing: changed ? TextRange.empty : next.composing,
    );
  }

  /// Bold or italic is on: over all the selection, or for what's typed
  /// next.
  bool isActive(MarkType type) {
    final s = selection;
    if (!s.isValid) return false;
    return s.isCollapsed
        ? _typingStyles.contains(type)
        : _model.covers(type, s.start, s.end);
  }

  /// B or I: over the selection, or for what's typed next.
  void toggle(MarkType type) {
    final s = selection;
    if (!s.isValid) return;
    if (s.isCollapsed) {
      final styles = {..._typingStyles};
      styles.contains(type) ? styles.remove(type) : styles.add(type);
      _typing = styles;
    } else {
      _model.toggleMark(type, s.start, s.end);
    }
    notifyListeners();
  }

  /// Return: a new paragraph, or the next list item.
  void insertParagraph() => _breakLine(_model.paragraph);

  /// Shift-Return: a plain line break.
  void insertLineBreak() => _breakLine(_model.lineBreak);

  void _breakLine(void Function(int start, int end) edit) {
    final s = selection;
    if (!s.isValid) return;
    // Typing carries on with the same bold/italic/strikethrough.
    final styles = _typingStyles;
    _model.tracked = [s.start];
    edit(s.start, s.end);
    super.value = TextEditingValue(
      text: _model.text,
      selection: TextSelection.collapsed(offset: _model.tracked.first),
    );
    _typing = styles;
  }

  /// The lines touched by the selection are a [kind] list.
  bool isList(ListKind kind) {
    final s = selection;
    if (!s.isValid) return false;
    final lineStart = s.start == 0
        ? 0
        : text.lastIndexOf('\n', s.start - 1) + 1;
    return listPrefixOf(text.substring(lineStart))?.kind == kind;
  }

  void toggleList(ListKind kind) {
    final s = selection;
    if (!s.isValid) return;
    _model
      ..tracked = [s.baseOffset, s.extentOffset]
      ..toggleList(s.start, s.end, kind);
    final [base, extent] = _model.tracked;
    super.value = TextEditingValue(
      text: _model.text,
      selection: TextSelection(baseOffset: base, extentOffset: extent),
    );
  }

  /// The link the cursor or selection is in.
  Mark? get currentLink {
    final s = selection;
    if (!s.isValid) return null;
    final link = _model.linkAt(s.start);
    return link != null && s.end <= link.end ? link : null;
  }

  /// Links the selection to [url] (or unlinks it, null). With nothing
  /// selected: changes the link the cursor is in, or adds [url] itself as
  /// a link.
  void setLink(String? url) {
    final s = selection;
    if (!s.isValid) return;
    if (!s.isCollapsed) {
      _model.setLink(s.start, s.end, url);
      notifyListeners();
      return;
    }
    if (currentLink case final link?) {
      _model.setLink(link.start, link.end, url);
      notifyListeners();
      return;
    }
    if (url == null) return;
    _model
      ..tracked = [s.start]
      ..replace(s.start, s.start, url, style: _typingStyles)
      ..setLink(s.start, s.start + url.length, url);
    super.value = TextEditingValue(
      text: _model.text,
      selection: TextSelection.collapsed(offset: _model.tracked.first),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final accent = Theme.of(context).colorScheme.primary;
    final muted = context.colors.mutedText;
    final text = this.text;
    // Cut wherever a mark or a list prefix starts or ends.
    final prefixes = <(int, int)>[];
    var lineStart = 0;
    for (final line in text.split('\n')) {
      if (listPrefixOf(line) case final p?) {
        prefixes.add((lineStart, lineStart + p.length));
      }
      lineStart += line.length + 1;
    }
    // The gap between paragraphs: an empty line, drawn half height.
    final gaps = {
      for (var i = 0; i < text.length; i++)
        if (text.codeUnitAt(i) == 0x0A &&
            (i == 0 || text.codeUnitAt(i - 1) == 0x0A))
          i,
    };
    final cuts = {
      0,
      text.length,
      for (final m in _model.marks) ...[m.start, m.end],
      for (final (s, e) in prefixes) ...[s, e],
      for (final g in gaps) ...[g, g + 1],
    }.where((x) => x >= 0 && x <= text.length).toList()..sort();
    final fontSize = style?.fontSize ?? 14;
    return TextSpan(
      style: style,
      children: [
        for (var i = 0; i + 1 < cuts.length; i++)
          () {
            final (s, e) = (cuts[i], cuts[i + 1]);
            bool has(MarkType t) => _model.marks.any(
              (m) => m.type == t && m.start <= s && e <= m.end,
            );
            final isPrefix = prefixes.any((p) => p.$1 <= s && e <= p.$2);
            final link = has(MarkType.link);
            final struck = has(MarkType.strike);
            return TextSpan(
              text: text.substring(s, e),
              style: TextStyle(
                fontSize: gaps.contains(s) ? fontSize / 2 : null,
                fontWeight: has(MarkType.bold) ? FontWeight.w700 : null,
                fontStyle: has(MarkType.italic) ? FontStyle.italic : null,
                color: link
                    ? accent
                    : isPrefix
                    ? muted
                    : null,
                decoration: TextDecoration.combine([
                  if (link) TextDecoration.underline,
                  if (struck) TextDecoration.lineThrough,
                ]),
                decorationColor: link ? accent : null,
              ),
            );
          }(),
      ],
    );
  }
}

/// A description field with a small toolbar: bold, italic, strikethrough,
/// link, bulleted and numbered lists. Nothing else on purpose. ⌘B, ⌘I,
/// ⌘⇧X and ⌘K work too. Return starts a new paragraph (or list item);
/// Shift-Return breaks the line.
class RichTextEditor extends StatefulWidget {
  const RichTextEditor({
    super.key,
    required this.controller,
    this.fontSize = 12,
    this.minLines = 6,
    this.hintText,
  });

  final RichTextController controller;
  final double fontSize;
  final int minLines;
  final String? hintText;

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  RichTextController get _c => widget.controller;

  Future<void> _editLink() async {
    final link = _c.currentLink;
    final result = await showDialog<_LinkResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _LinkDialog(url: link?.url),
    );
    if (!mounted) return;
    switch (result) {
      case _LinkSet(:final url):
        _c.setLink(url);
      case _LinkRemoved():
        _c.setLink(null);
      case null:
        break;
    }
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            _c.toggle(MarkType.bold),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            _c.toggle(MarkType.italic),
        const SingleActivator(
          LogicalKeyboardKey.keyX,
          meta: true,
          shift: true,
        ): () =>
            _c.toggle(MarkType.strike),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _editLink,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          // Counts as part of the field: clicking it doesn't unfocus it.
          TextFieldTapRegion(
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) => _toolbar(context),
            ),
          ),
          Focus(
            // Return and Shift-Return, before the text field inserts a
            // plain "\n" (except while composing, e.g. a Japanese IME).
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKey,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              // Never scrolls (or bounces) on its own: a swipe over it
              // scrolls the form instead.
              scrollPhysics: const NeverScrollableScrollPhysics(),
              style: TextStyle(fontSize: widget.fontSize),
              // Grows with its text rather than scrolling inside.
              minLines: widget.minLines,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: widget.fontSize,
                  color: context.colors.placeholder,
                ),
                enabledBorder: context.colors.fieldBorder,
                border: context.colors.fieldBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (_c.value.composing.isValid ||
        keys.isMetaPressed ||
        keys.isControlPressed ||
        keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    keys.isShiftPressed ? _c.insertLineBreak() : _c.insertParagraph();
    return KeyEventResult.handled;
  }

  Widget _toolbar(BuildContext context) {
    final link = _c.currentLink;
    return Row(
      spacing: 2,
      children: [
        _ToolButton(
          icon: Symbols.format_bold,
          tooltip: 'Bold (⌘B)',
          active: _c.isActive(MarkType.bold),
          onPressed: () => _c.toggle(MarkType.bold),
        ),
        _ToolButton(
          icon: Symbols.format_italic,
          tooltip: 'Italic (⌘I)',
          active: _c.isActive(MarkType.italic),
          onPressed: () => _c.toggle(MarkType.italic),
        ),
        _ToolButton(
          icon: Symbols.format_strikethrough,
          tooltip: 'Strikethrough (⌘⇧X)',
          active: _c.isActive(MarkType.strike),
          onPressed: () => _c.toggle(MarkType.strike),
        ),
        _ToolButton(
          icon: Symbols.link,
          tooltip: 'Link (⌘K)',
          active: link != null,
          onPressed: _editLink,
        ),
        const SizedBox(width: 6),
        _ToolButton(
          icon: Symbols.format_list_bulleted,
          tooltip: 'Bulleted list',
          active: _c.isList(ListKind.bullet),
          onPressed: () => _c.toggleList(ListKind.bullet),
        ),
        _ToolButton(
          icon: Symbols.format_list_numbered,
          tooltip: 'Numbered list',
          active: _c.isList(ListKind.numbered),
          onPressed: () => _c.toggleList(ListKind.numbered),
        ),
        // In a link: where it goes, and a button to open it.
        if (link != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              link.url ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11.5, color: context.colors.mutedText),
            ),
          ),
          _ToolButton(
            icon: Symbols.open_in_new,
            tooltip: 'Open link',
            onPressed: () => openLink(link.url ?? ''),
          ),
        ],
      ],
    );
  }
}

/// Opens [url] in the browser (or whatever handles it).
Future<void> openLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri);
}

/// An address as typed, made openable: "example.com" → "https://example.com".
String normalizeUrl(String input) {
  final url = input.trim();
  if (url.isEmpty) return url;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(url);
  return hasScheme ? url : 'https://$url';
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 26,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      iconSize: 18,
      // On: a filled square, like a hovered button.
      style: active
          ? IconButton.styleFrom(backgroundColor: context.colors.hoverStrong)
          : null,
      icon: Icon(icon),
    ),
  );
}

sealed class _LinkResult {
  const _LinkResult();
}

final class _LinkSet extends _LinkResult {
  const _LinkSet(this.url);
  final String url;
}

final class _LinkRemoved extends _LinkResult {
  const _LinkRemoved();
}

/// Asks for a link's address; Remove when editing one.
class _LinkDialog extends StatefulWidget {
  const _LinkDialog({this.url});
  final String? url;

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _input = TextEditingController(text: widget.url);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final url = normalizeUrl(_input.text);
    Navigator.pop(context, url.isEmpty ? null : _LinkSet(url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: Text(widget.url == null ? 'Add link' : 'Edit link'),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _input,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'https://',
            hintStyle: TextStyle(color: context.colors.placeholder),
            enabledBorder: context.colors.fieldBorder,
            border: context.colors.fieldBorder,
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        if (widget.url != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _LinkRemoved()),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ListenableBuilder(
          listenable: _input,
          builder: (context, _) => FilledButton(
            onPressed: _input.text.trim().isEmpty ? null : _save,
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
