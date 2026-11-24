/// The task description's formatting: bold, italic, strikethrough, links,
/// bulleted and numbered lists, headings (three sizes) and paragraphs (a
/// blank line between). Nothing else (no images, quotes…).
///
/// The text is plain, with list items marked by a prefix at the start of
/// their line ("• " or "1. "), so lists edit like the text they look like.
/// Bold, italic and links are [Mark]s: ranges over the text. Headings are
/// a level per line ([RichTextModel.headings]).
///
/// Saved as a small Markdown subset (see [RichTextModel.toMarkdown]):
/// `**bold**`, `*italic*`, `~~struck~~`, `[text](url)`, `- item`,
/// `1. item`, `# heading` (to `###`), and a blank line between
/// paragraphs. A plain description from before is read as is.
library;

enum MarkType { bold, italic, strike, link }

/// Bold, italic or a link over `[start, end)` of the text.
final class Mark {
  const Mark(this.type, this.start, this.end, [this.url]);
  final MarkType type;
  final int start, end;

  /// For a link.
  final String? url;

  Mark withRange(int start, int end) => Mark(type, start, end, url);

  @override
  bool operator ==(Object other) =>
      other is Mark &&
      other.type == type &&
      other.start == start &&
      other.end == end &&
      other.url == url;

  @override
  int get hashCode => Object.hash(type, start, end, url);

  @override
  String toString() =>
      'Mark(${type.name}, $start, $end${url == null ? '' : ', $url'})';
}

enum ListKind { bullet, numbered }

const bulletPrefix = '• ';
final _numberedPrefix = RegExp(r'^(\d+)\. ');

/// The largest heading: H1 to H3, nothing larger.
const maxHeading = 3;
final _headingPrefix = RegExp(r'^(#{1,3}) ');

/// The list prefix a line starts with, if it's a list item.
({ListKind kind, int length})? listPrefixOf(String line) {
  if (line.startsWith(bulletPrefix)) {
    return (kind: ListKind.bullet, length: bulletPrefix.length);
  }
  if (_numberedPrefix.firstMatch(line) case final m?) {
    return (kind: ListKind.numbered, length: m.end);
  }
  return null;
}

/// Inline styles that typing carries on with.
const textStyles = {MarkType.bold, MarkType.italic, MarkType.strike};

/// The editable state: [text] and its [marks]. Edits keep the marks in
/// place, and move any offsets in [tracked] (the selection) along.
class RichTextModel {
  RichTextModel([
    this.text = '',
    List<Mark> marks = const [],
    List<int>? headings,
  ]) : marks = _normalize(marks, text.length),
       headings = [
         for (var i = 0; i <= '\n'.allMatches(text).length; i++)
           headings != null && i < headings.length ? headings[i] : 0,
       ];

  String text;
  List<Mark> marks;

  /// Each line's heading level: 1 to [maxHeading], or 0 for plain text.
  /// One per line, kept in step as lines come and go.
  List<int> headings;

  /// Offsets moved along by every edit, like a cursor would be.
  List<int> tracked = [];

  // ---------------------------------------------------------------------
  // Editing

  /// Replaces `[start, end)` with [inserted]. Marks around it stay put and
  /// marks spanning it stretch to cover the new text. With [style], the
  /// new text is exactly that bold/italic (what's being typed with);
  /// links never grow at their edges.
  void replace(int start, int end, String inserted, {Set<MarkType>? style}) {
    assert(0 <= start && start <= end && end <= text.length);
    final delta = inserted.length - (end - start);
    final insEnd = start + inserted.length;
    // A mark starting where the new text goes starts after it; one ending
    // there ends before it. So only a mark around the replaced text (not
    // just touching it) covers what replaced it.
    int markStart(int x) => x < start
        ? x
        : x >= end
        ? x + delta
        : insEnd;
    int markEnd(int x) => x <= start
        ? x
        : x >= end
        ? x + delta
        : start;
    _shiftHeadings(start, end, inserted);
    text = text.replaceRange(start, end, inserted);
    var next = [
      for (final m in marks) m.withRange(markStart(m.start), markEnd(m.end)),
    ];
    if (style != null && inserted.isNotEmpty) {
      for (final type in textStyles) {
        next = _without(next, type, start, insEnd);
        if (style.contains(type)) next.add(Mark(type, start, insEnd));
      }
    }
    marks = _normalize(next, text.length);
    tracked = [
      for (final x in tracked)
        x < start
            ? x
            : x >= end
            ? x + delta
            : insEnd,
    ];
  }

  /// Before `[start, end)` is replaced with [inserted]: [headings] for
  /// the lines after. Lines joined keep the first one's level (or, when
  /// whole lines are taken out, the next one's); lines split off are
  /// plain, the line's level staying with its text.
  void _shiftHeadings(int start, int end, String inserted) {
    int breaks(String s) => '\n'.allMatches(s).length;
    final line = breaks(text.substring(0, start));
    final removed = breaks(text.substring(start, end));
    final added = breaks(inserted);
    if (removed == 0 && added == 0) return;
    final atLineStart = start == _lineStart(start);
    final wholeLines =
        atLineStart && removed > 0 && (end == 0 || text[end - 1] == '\n');
    final level = headings[wholeLines ? line + removed : line];
    // Split at the start of the line: the text (and its level) moves down.
    final textLast = atLineStart && end == start;
    headings = [
      ...headings.sublist(0, line),
      if (textLast) ...List.filled(added, 0),
      level,
      if (!textLast) ...List.filled(added, 0),
      ...headings.sublist(line + removed + 1),
    ];
  }

  /// Bold or italic on (or off) over `[start, end)`.
  void setMark(MarkType type, int start, int end, {required bool on}) {
    var next = _without(marks, type, start, end);
    if (on && start < end) next = [...next, Mark(type, start, end)];
    marks = _normalize(next, text.length);
  }

  /// Turns bold or italic on over `[start, end)`, or off if it's all
  /// that already.
  void toggleMark(MarkType type, int start, int end) {
    if (start == end) return;
    setMark(type, start, end, on: !covers(type, start, end));
  }

  /// Makes `[start, end)` a link to [url], or not a link (null).
  void setLink(int start, int end, String? url) {
    var next = _without(marks, MarkType.link, start, end);
    if (url != null && start < end) {
      next = [...next, Mark(MarkType.link, start, end, url)];
    }
    marks = _normalize(next, text.length);
  }

  /// `[start, end)` is all [type].
  bool covers(MarkType type, int start, int end) {
    var at = start;
    for (final m in marks.where((m) => m.type == type)) {
      if (m.start <= at && m.end > at) at = m.end;
      if (at >= end) return true;
    }
    return at >= end;
  }

  /// The bold/italic that typing at [offset] continues: the character
  /// before it's (the first one's, at the start).
  Set<MarkType> stylesAt(int offset) {
    final char = offset > 0 ? offset - 1 : 0;
    return {
      for (final m in marks)
        if (textStyles.contains(m.type) && m.start <= char && char < m.end)
          m.type,
    };
  }

  /// The link at [offset] (its edges included).
  Mark? linkAt(int offset) => marks
      .where(
        (m) => m.type == MarkType.link && m.start <= offset && offset <= m.end,
      )
      .firstOrNull;

  // ---------------------------------------------------------------------
  // Lines and lists

  /// The start offset of each line.
  List<int> get lineStarts => [
    0,
    for (var i = 0; i < text.length; i++)
      if (text.codeUnitAt(i) == 0x0A) i + 1,
  ];

  int _lineStart(int offset) =>
      offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

  int _lineEnd(int offset) {
    final i = text.indexOf('\n', offset);
    return i == -1 ? text.length : i;
  }

  String _lineAt(int start) => text.substring(start, _lineEnd(start));

  /// The start offsets of the lines `[start, end)` touches. A selection
  /// ending at the very start of a line doesn't take it in.
  List<int> _linesIn(int start, int end) {
    final first = _lineStart(start);
    return [
      for (final s in lineStarts)
        if (s == first || (s > first && s < end)) s,
    ];
  }

  int _lineIndex(int offset) =>
      '\n'.allMatches(text.substring(0, _lineStart(offset))).length;

  /// The heading level of the line [offset] is in (0: plain text).
  int headingAt(int offset) => headings[_lineIndex(offset)];

  /// Makes the lines `[start, end)` touches headings of [level] (0: plain
  /// text). A heading isn't a list item too: their prefixes come off.
  void setHeading(int start, int end, int level) {
    assert(0 <= level && level <= maxHeading);
    final lines = _linesIn(start, end);
    final first = _lineIndex(start);
    for (var i = first; i < first + lines.length; i++) {
      headings[i] = level;
    }
    if (level == 0) return;
    // From the last line up, so earlier offsets stay valid.
    for (final s in lines.reversed) {
      if (listPrefixOf(_lineAt(s)) case final p?) {
        replace(s, s + p.length, '');
      }
    }
    renumber();
  }

  /// Makes the lines `[start, end)` touches into a [kind] list, or plain
  /// lines if they all are one already. A list item isn't a heading.
  void toggleList(int start, int end, ListKind kind) {
    final lines = _linesIn(start, end);
    final all = lines.every((s) => listPrefixOf(_lineAt(s))?.kind == kind);
    if (!all) {
      final first = _lineIndex(start);
      for (var i = first; i < first + lines.length; i++) {
        headings[i] = 0;
      }
    }
    // From the last line up, so earlier offsets stay valid.
    for (final s in lines.reversed) {
      final prefix = listPrefixOf(_lineAt(s));
      final replacement = all
          ? ''
          : kind == ListKind.bullet
          ? bulletPrefix
          : '1. ';
      replace(s, s + (prefix?.length ?? 0), replacement);
    }
    renumber();
  }

  /// Return over `[start, end)`: a new paragraph (a blank line between),
  /// or in a list the next item, or on an empty item the end of the list.
  void paragraph(int start, int end) {
    replace(start, end, '');
    final ls = _lineStart(start), le = _lineEnd(start);
    final line = text.substring(ls, le);
    final prefix = listPrefixOf(line);
    if (prefix != null) {
      if (line.length == prefix.length) {
        // An empty item ends the list: it becomes the gap after it.
        replace(ls, le, '');
        replace(ls, ls, '\n', style: const {});
      } else {
        final next = prefix.kind == ListKind.bullet ? bulletPrefix : '1. ';
        replace(start, start, '\n$next', style: const {});
      }
    } else {
      // One line break is enough where there's already a gap: on an empty
      // line, or at the start of a line after one.
      final gap =
          line.isEmpty ||
          (start == ls && (ls == 0 || _lineStart(ls - 1) == ls - 1));
      replace(start, start, gap ? '\n' : '\n\n', style: const {});
    }
    renumber();
  }

  /// Shift-Return over `[start, end)`: a plain line break (in a list, a
  /// second line in the same item).
  void lineBreak(int start, int end) {
    replace(start, end, '\n', style: const {});
    renumber();
  }

  /// After a line break arrived some other way (pasted, or typed without
  /// the Return handling) at [offset], the "\n" already there: in a list,
  /// the new line is the next item, or, on an empty item, the list ends.
  void afterNewline(int offset) {
    final lineStart = _lineStart(offset);
    final line = text.substring(lineStart, offset);
    final prefix = listPrefixOf(line);
    if (prefix == null) return;
    // Empty: nothing before the break but the prefix, nothing after it.
    if (line.length == prefix.length && _lineEnd(offset + 1) == offset + 1) {
      // An empty item: Return ends the list (the item and the new line
      // become one plain line).
      replace(lineStart, offset + 1, '');
      return;
    }
    replace(
      offset + 1,
      offset + 1,
      prefix.kind == ListKind.bullet ? bulletPrefix : '1. ',
    );
    renumber();
  }

  /// Where Backspace at [offset] should take a list item's whole prefix
  /// off (just after it): the prefix's range, or null for an ordinary
  /// Backspace.
  (int, int)? prefixBefore(int offset) {
    final lineStart = _lineStart(offset);
    final prefix = listPrefixOf(_lineAt(lineStart));
    if (prefix == null || offset != lineStart + prefix.length) return null;
    return (lineStart, offset);
  }

  /// Numbers each run of numbered items 1, 2, 3… A run goes on through
  /// an item's second lines (Shift-Return); a blank line or a bulleted
  /// item ends it.
  void renumber() {
    final fixes = <(int, int, String)>[];
    var n = 0;
    for (final s in lineStarts) {
      final line = _lineAt(s);
      if (_numberedPrefix.firstMatch(line) case final m?) {
        n++;
        if (m.group(1) != '$n') fixes.add((s, s + m.group(1)!.length, '$n'));
      } else if (line.isEmpty || line.startsWith(bulletPrefix)) {
        n = 0;
      }
    }
    for (final (start, end, number) in fixes.reversed) {
      replace(start, end, number);
    }
  }

  // ---------------------------------------------------------------------
  // Markdown

  /// The Markdown subset it's saved as. Each line closes what it opens.
  String toMarkdown() {
    final out = StringBuffer();
    final starts = lineStarts;
    for (final (i, s) in starts.indexed) {
      if (i > 0) out.write('\n');
      final e = _lineEnd(s);
      final line = text.substring(s, e);
      final prefix = listPrefixOf(line);
      final level = headings[i];
      if (level > 0) {
        out.write('${'#' * level} ');
      } else if (prefix?.kind == ListKind.bullet) {
        out.write('- ');
      } else if (prefix != null) {
        out.write(line.substring(0, prefix.length));
      }
      final from = s + (level > 0 ? 0 : prefix?.length ?? 0);
      var inline = _inlineMarkdown(from, e);
      // A plain line that would read back as a list item or a heading.
      if (level == 0 && prefix == null) {
        if (inline.startsWith('- ') || _headingPrefix.hasMatch(inline)) {
          inline = '\\$inline';
        } else if (_numberedPrefix.firstMatch(inline) case final m?) {
          inline = '${m.group(1)}\\${inline.substring(m.group(1)!.length)}';
        }
      }
      out.write(inline);
    }
    return out.toString();
  }

  String _inlineMarkdown(int from, int to) {
    if (from >= to) return '';
    final cuts = {
      from,
      to,
      for (final m in marks) ...[m.start, m.end],
    }.where((x) => x >= from && x <= to).toList()..sort();
    final out = StringBuffer();
    var bold = false, italic = false, strike = false;
    String? link;
    void closeStyles() {
      if (strike) out.write('~~');
      if (italic) out.write('*');
      if (bold) out.write('**');
      bold = italic = strike = false;
    }

    for (var i = 0; i + 1 < cuts.length; i++) {
      final (s, e) = (cuts[i], cuts[i + 1]);
      bool has(MarkType t) =>
          marks.any((m) => m.type == t && m.start <= s && e <= m.end);
      final url = marks
          .where((m) => m.type == MarkType.link && m.start <= s && e <= m.end)
          .firstOrNull
          ?.url;
      if (url != link) {
        closeStyles();
        if (link != null) out.write('](${_escapeUrl(link)})');
        if (url != null) out.write('[');
        link = url;
      }
      // Markers are toggles (see fromMarkdown), so they needn't nest: at
      // most "***" lands in one place, which reads back as one of each.
      if (has(MarkType.bold) != bold) {
        out.write('**');
        bold = !bold;
      }
      if (has(MarkType.italic) != italic) {
        out.write('*');
        italic = !italic;
      }
      if (has(MarkType.strike) != strike) {
        out.write('~~');
        strike = !strike;
      }
      out.write(_escape(text.substring(s, e)));
    }
    closeStyles();
    if (link != null) out.write('](${_escapeUrl(link)})');
    return out.toString();
  }

  static String _escape(String s) =>
      s.replaceAllMapped(RegExp(r'[\\*~\[\]]'), (m) => '\\${m[0]}');

  static String _escapeUrl(String url) =>
      url.replaceAll(' ', '%20').replaceAll(')', '%29');

  /// Reads [toMarkdown]'s format back. Anything else is plain text: a
  /// `*` or `**` with no partner on its line stays a literal character.
  factory RichTextModel.fromMarkdown(String markdown) {
    final text = StringBuffer();
    final marks = <Mark>[];
    final headings = <int>[];
    for (final (i, line) in markdown.split('\n').indexed) {
      if (i > 0) text.write('\n');
      var rest = line;
      final heading = _headingPrefix.firstMatch(rest);
      headings.add(heading?.group(1)!.length ?? 0);
      if (heading != null) {
        rest = rest.substring(heading.end);
      } else if (rest.startsWith('- ')) {
        text.write(bulletPrefix);
        rest = rest.substring(2);
      } else if (_numberedPrefix.firstMatch(rest) case final m?) {
        text.write(m[0]);
        rest = rest.substring(m.end);
      }
      _parseInline(rest, text, marks);
    }
    return RichTextModel(text.toString(), marks, headings);
  }

  static final _link = RegExp(r'\]\(([^)\s]*)\)');

  static void _parseInline(String s, StringBuffer text, List<Mark> marks) {
    // Tokens: a literal character, or a bold/italic toggle, or a link's
    // start/end.
    final tokens = <(String kind, String value)>[];
    // Where each link found so far ends: index of its "]" → its address
    // and the index after its ")".
    final linkEnds = <int, ({String url, int end})>{};
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '\\' && i + 1 < s.length) {
        tokens.add(('char', s[++i]));
      } else if (s.startsWith('~~', i)) {
        tokens.add(('strike', ''));
        i++;
      } else if (s.startsWith('**', i)) {
        tokens.add(('bold', ''));
        i++;
      } else if (c == '*') {
        tokens.add(('italic', ''));
      } else if (c == '[') {
        final close = _closingBracket(s, i + 1);
        final m = close == null ? null : _link.matchAsPrefix(s, close);
        if (m != null) {
          tokens.add(('linkStart', ''));
          linkEnds[close!] = (url: m[1]!, end: m.end);
        } else {
          tokens.add(('char', c));
        }
      } else if (linkEnds.remove(i) case final link?) {
        tokens.add(('linkEnd', _decodeUrl(link.url)));
        i = link.end - 1;
      } else {
        tokens.add(('char', c));
      }
    }
    // An odd toggle out (no partner) is a literal: the last one.
    for (final (kind, literal) in [
      ('bold', '**'),
      ('italic', '*'),
      ('strike', '~~'),
    ]) {
      final at = [
        for (final (i, t) in tokens.indexed)
          if (t.$1 == kind) i,
      ];
      if (at.length.isOdd) tokens[at.last] = ('char', literal);
    }
    final open = <MarkType, int>{};
    int? linkStart;
    for (final (kind, value) in tokens) {
      final at = text.length;
      switch (kind) {
        case 'char':
          text.write(value);
        case 'bold' || 'italic' || 'strike':
          final type = switch (kind) {
            'bold' => MarkType.bold,
            'italic' => MarkType.italic,
            _ => MarkType.strike,
          };
          if (open.remove(type) case final start?) {
            marks.add(Mark(type, start, at));
          } else {
            open[type] = at;
          }
        case 'linkStart':
          linkStart = at;
        case 'linkEnd':
          if (linkStart != null) {
            marks.add(Mark(MarkType.link, linkStart, at, value));
          }
          linkStart = null;
      }
    }
  }

  static String _decodeUrl(String url) {
    try {
      return Uri.decodeFull(url);
    } on ArgumentError {
      return url;
    }
  }

  /// The index of the `]` closing a `[` (unescaped), or null.
  static int? _closingBracket(String s, int from) {
    for (var i = from; i < s.length; i++) {
      if (s[i] == '\\') {
        i++;
      } else if (s[i] == ']') {
        return i;
      } else if (s[i] == '[') {
        return null;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------

  /// [marks] with [type] taken off `[start, end)` (marks split around it).
  static List<Mark> _without(
    List<Mark> marks,
    MarkType type,
    int start,
    int end,
  ) => [
    for (final m in marks)
      if (m.type != type || m.end <= start || m.start >= end)
        m
      else ...[
        if (m.start < start) m.withRange(m.start, start),
        if (m.end > end) m.withRange(end, m.end),
      ],
  ];

  /// Sorted, inside the text, no empty marks, and overlapping or touching
  /// marks of a kind joined (links only with the same address).
  static List<Mark> _normalize(List<Mark> marks, int length) {
    final sorted = [
      for (final m in marks)
        if (m.start.clamp(0, length) < m.end.clamp(0, length))
          m.withRange(m.start.clamp(0, length), m.end.clamp(0, length)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final out = <Mark>[];
    for (final m in sorted) {
      final i = out.lastIndexWhere(
        (o) => o.type == m.type && o.url == m.url && o.end >= m.start,
      );
      if (i != -1) {
        final o = out[i];
        out[i] = o.withRange(o.start, m.end > o.end ? m.end : o.end);
      } else {
        out.add(m);
      }
    }
    return out..sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.type.index.compareTo(b.type.index),
    );
  }
}
