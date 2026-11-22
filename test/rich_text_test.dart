import 'package:codename/tasks/rich_text/rich_text_editor.dart';
import 'package:codename/tasks/rich_text/rich_text_model.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const b = MarkType.bold, i = MarkType.italic, l = MarkType.link;

  group('Markdown', () {
    test('plain text reads back as is', () {
      final m = RichTextModel.fromMarkdown('Call Ada\nthen ship it.');
      expect(m.text, 'Call Ada\nthen ship it.');
      expect(m.marks, isEmpty);
      expect(m.toMarkdown(), 'Call Ada\nthen ship it.');
    });

    test('bold, italic and links', () {
      final m = RichTextModel.fromMarkdown(
        'A **bold** and *italic* [link](https://x.com/a)',
      );
      expect(m.text, 'A bold and italic link');
      expect(m.marks, [
        const Mark(b, 2, 6),
        const Mark(i, 11, 17),
        const Mark(l, 18, 22, 'https://x.com/a'),
      ]);
    });

    test('lists read as prefixed lines', () {
      final m = RichTextModel.fromMarkdown('- one\n- two\n1. first\n2. second');
      expect(m.text, '• one\n• two\n1. first\n2. second');
      expect(m.toMarkdown(), '- one\n- two\n1. first\n2. second');
    });

    test('round-trips overlapping styles and styles inside links', () {
      final m = RichTextModel('bold both italic link', [
        const Mark(b, 0, 9),
        const Mark(i, 5, 16),
        const Mark(l, 17, 21, 'https://a.b/c d)'),
        const Mark(b, 17, 21),
      ]);
      final md = m.toMarkdown();
      final back = RichTextModel.fromMarkdown(md);
      expect(back.text, m.text, reason: md);
      expect(back.marks, m.marks, reason: md);
    });

    test('characters that mean formatting are escaped', () {
      final m = RichTextModel('2 * 3 = [6] \\ ok\n- not a list\n1. nor this');
      final back = RichTextModel.fromMarkdown(m.toMarkdown());
      expect(back.text, m.text);
      expect(back.marks, isEmpty);
    });

    test('a marker with no partner is a literal', () {
      final m = RichTextModel.fromMarkdown('5 * 3 and **half');
      expect(m.text, '5 * 3 and **half');
      expect(m.marks, isEmpty);
    });

    test('styles across lines are closed and reopened per line', () {
      final m = RichTextModel('one\ntwo', [const Mark(b, 0, 7)]);
      expect(m.toMarkdown(), '**one**\n**two**');
    });
  });

  group('editing', () {
    test('typing inside a mark grows it; at its edges, only with the '
        'style being typed', () {
      final m = RichTextModel('ab', [const Mark(b, 0, 2)]);
      m.replace(1, 1, 'x', style: {b});
      expect(m.marks, [const Mark(b, 0, 3)]);
      m.replace(3, 3, 'y', style: {b});
      expect(m.marks, [const Mark(b, 0, 4)]);
      m.replace(4, 4, 'z', style: {});
      expect(m.text, 'axbyz');
      expect(m.marks, [const Mark(b, 0, 4)]);
    });

    test('links don’t grow at their edges', () {
      final m = RichTextModel('go', [const Mark(l, 0, 2, 'u')]);
      m.replace(2, 2, '!', style: {});
      m.replace(0, 0, '>', style: {});
      expect(m.marks, [const Mark(l, 1, 3, 'u')]);
    });

    test('deleting shrinks and drops marks; the selection moves along', () {
      final m = RichTextModel('hello world', [
        const Mark(b, 0, 5),
        const Mark(i, 6, 11),
      ])..tracked = [11];
      m.replace(3, 8, '');
      expect(m.text, 'helrld');
      expect(m.marks, [const Mark(b, 0, 3), const Mark(i, 3, 6)]);
      expect(m.tracked, [6]);
    });

    test('toggling a style on and off', () {
      final m = RichTextModel('abcdef', [const Mark(b, 0, 3)]);
      m.toggleMark(b, 1, 5);
      expect(m.marks, [const Mark(b, 0, 5)]);
      m.toggleMark(b, 1, 3);
      expect(m.marks, [const Mark(b, 0, 1), const Mark(b, 3, 5)]);
      expect(m.covers(b, 3, 5), isTrue);
      expect(m.covers(b, 0, 2), isFalse);
    });

    test('typing continues the style before the cursor', () {
      final m = RichTextModel('ab cd', [const Mark(i, 0, 2)]);
      expect(m.stylesAt(2), {i});
      expect(m.stylesAt(3), isEmpty);
      expect(m.stylesAt(0), {i}, reason: 'the first character’s');
    });

    test('links are set, replaced and removed', () {
      final m = RichTextModel('see docs here');
      m.setLink(4, 8, 'https://a');
      expect(m.linkAt(6)?.url, 'https://a');
      m.setLink(4, 8, 'https://b');
      expect(m.marks, [const Mark(l, 4, 8, 'https://b')]);
      m.setLink(4, 8, null);
      expect(m.marks, isEmpty);
    });
  });

  group('lists', () {
    test('toggling makes each selected line an item, and back', () {
      final m = RichTextModel('one\ntwo\nthree')..tracked = [0, 7];
      m.toggleList(0, 7, ListKind.bullet);
      expect(m.text, '• one\n• two\nthree');
      expect(m.tracked, [2, 11], reason: 'the selection moves with it');
      m.toggleList(2, 11, ListKind.numbered);
      expect(m.text, '1. one\n2. two\nthree');
      m.toggleList(0, 0, ListKind.numbered);
      expect(m.text, 'one\n1. two\nthree', reason: 'just the caret’s line');
    });

    test('Return adds the next item; on an empty item it ends the list', () {
      final m = RichTextModel('1. one');
      m.replace(6, 6, '\n');
      m.afterNewline(6);
      expect(m.text, '1. one\n2. ');
      m.replace(10, 10, '\n');
      m.afterNewline(10);
      expect(m.text, '1. one\n');
    });

    test('Backspace just after a prefix takes the whole prefix off', () {
      final m = RichTextModel('x\n• item');
      expect(m.prefixBefore(4), (2, 4));
      expect(m.prefixBefore(5), isNull);
      expect(m.prefixBefore(1), isNull);
    });

    test('numbered runs are renumbered', () {
      final m = RichTextModel('3. a\n7. b\n\n5. c\nmore\n9. d');
      m.renumber();
      expect(
        m.text,
        '1. a\n2. b\n\n1. c\nmore\n2. d',
        reason: 'a blank line restarts; an item’s second line doesn’t',
      );
    });
  });

  group('paragraphs and line breaks', () {
    test('Return leaves a blank line between paragraphs', () {
      final m = RichTextModel('one')..tracked = [3];
      m.paragraph(3, 3);
      expect(m.text, 'one\n\n');
      expect(m.tracked, [5]);
      m.paragraph(5, 5);
      expect(m.text, 'one\n\n\n', reason: 'already a gap: one more line');
    });

    test('Return splits a paragraph; over a selection, replaces it', () {
      final m = RichTextModel('abcd')..tracked = [1];
      m.paragraph(1, 3);
      expect(m.text, 'a\n\nd');
      expect(m.tracked, [3]);
    });

    test('Shift-Return is one line break; in a list, the same item', () {
      final plain = RichTextModel('ab')..lineBreak(1, 1);
      expect(plain.text, 'a\nb');
      final item = RichTextModel('1. ab\n2. c')..lineBreak(4, 4);
      expect(item.text, '1. a\nb\n2. c', reason: 'numbering goes on');
    });

    test('Return in a list adds an item; on an empty one, ends the list '
        'with a gap', () {
      final m = RichTextModel('• one')..tracked = [5];
      m.paragraph(5, 5);
      expect(m.text, '• one\n• ');
      m.paragraph(m.tracked.first, m.tracked.first);
      expect(m.text, '• one\n\n');
      expect(m.tracked, [7]);
    });

    test('Return at the start of an item’s text keeps it an item', () {
      final m = RichTextModel('1. one')..tracked = [3];
      m.paragraph(3, 3);
      expect(m.text, '1. \n2. one');
    });

    test('paragraphs round-trip as Markdown blank lines', () {
      final m = RichTextModel.fromMarkdown('First\n\nSecond\nline');
      expect(m.text, 'First\n\nSecond\nline');
      expect(m.toMarkdown(), 'First\n\nSecond\nline');
    });
  });

  group('strikethrough', () {
    test('round-trips with other styles; a lone ~ stays literal', () {
      final m = RichTextModel.fromMarkdown('~~gone~~ and ***~~all~~***');
      expect(m.text, 'gone and all');
      expect(m.marks, [
        const Mark(MarkType.strike, 0, 4),
        const Mark(b, 9, 12),
        const Mark(i, 9, 12),
        const Mark(MarkType.strike, 9, 12),
      ]);
      expect(RichTextModel.fromMarkdown(m.toMarkdown()).marks, m.marks);
      final plain = RichTextModel('about ~5 or ~~x');
      expect(RichTextModel.fromMarkdown(plain.toMarkdown()).text, plain.text);
    });

    test('typing continues it', () {
      final m = RichTextModel('x', [const Mark(MarkType.strike, 0, 1)]);
      expect(m.stylesAt(1), {MarkType.strike});
    });
  });

  group('RichTextController', () {
    // Types [s] at the cursor, as the text field would.
    void type(RichTextController c, String s) {
      final at = c.selection.start;
      c.value = TextEditingValue(
        text: c.text.replaceRange(at, c.selection.end, s),
        selection: TextSelection.collapsed(offset: at + s.length),
      );
    }

    test('bold on with nothing selected applies to what’s typed', () {
      final c = RichTextController.fromMarkdown('Hi ')
        ..selection = const TextSelection.collapsed(offset: 3);
      c.toggle(b);
      expect(c.isActive(b), isTrue);
      type(c, 'there');
      c.toggle(b);
      type(c, '!');
      expect(c.toMarkdown(), 'Hi **there**!');
    });

    test('Return continues a list; Backspace after a prefix removes it', () {
      final c = RichTextController.fromMarkdown('- one')
        ..selection = const TextSelection.collapsed(offset: 5);
      type(c, '\n');
      expect(c.text, '• one\n• ');
      expect(c.selection.baseOffset, 8);
      c.value = TextEditingValue(
        text: '• one\n•',
        selection: const TextSelection.collapsed(offset: 7),
      );
      expect(c.text, '• one\n');
      expect(c.selection.baseOffset, 6);
    });

    test('a link wraps the selection, or is typed in at the cursor', () {
      final c = RichTextController.fromMarkdown('read the docs')
        ..selection = const TextSelection(baseOffset: 9, extentOffset: 13);
      c.setLink('https://d');
      expect(c.toMarkdown(), 'read the [docs](https://d)');
      c.selection = const TextSelection.collapsed(offset: 11);
      expect(c.currentLink?.url, 'https://d');
      c.setLink(null);
      expect(c.toMarkdown(), 'read the docs');
      c.selection = const TextSelection.collapsed(offset: 0);
      c.setLink('https://x');
      expect(c.toMarkdown(), '[https://x](https://x)read the docs');
    });

    test('addresses without a scheme get https', () {
      expect(normalizeUrl(' example.com '), 'https://example.com');
      expect(normalizeUrl('mailto:a@b.c'), 'mailto:a@b.c');
    });
  });
}
