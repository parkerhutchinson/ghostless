import 'package:codename/tasks/label_field.dart';
import 'package:codename/tasks/project_labels.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final long = 'a' * 30;

  test('clipLabel trims and cuts to 25 characters', () {
    expect(clipLabel('  short  '), 'short');
    expect(clipLabel(long), 'a' * maxLabelLength);
    // Emoji count as one character each.
    expect(clipLabel('🎉' * 30).runes.length, maxLabelLength);
  });

  group('LabelLengthFormatter', () {
    const f = LabelLengthFormatter();
    TextEditingValue v(String t) => TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );

    test('typing past 25 does nothing', () {
      final full = 'b' * maxLabelLength;
      expect(f.formatEditUpdate(v(full), v('${full}c')).text, full);
    });

    test('each comma-separated label has its own 25', () {
      final ok = '${'b' * 25}, ${'c' * 25}';
      expect(f.formatEditUpdate(v(''), v(ok)).text, ok);
    });

    test('a paste is cut short, label by label', () {
      expect(
        f.formatEditUpdate(v(''), v('x, $long')).text,
        'x, ${'a' * maxLabelLength}',
      );
    });
  });
}
