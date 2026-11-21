import 'package:codename/settings/color_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('reads hex with or without #, any case, around spaces', () {
    expect(parseHexColor('#1E272B'), const Color(0xFF1E272B));
    expect(parseHexColor('1e272b'), const Color(0xFF1E272B));
    expect(parseHexColor('  #1E272B '), const Color(0xFF1E272B));
  });

  test('reads the short form', () {
    expect(parseHexColor('#abc'), const Color(0xFFAABBCC));
  });

  test('rejects anything else', () {
    for (final bad in ['', '#', '#12345', '#1234567', 'zzzzzz', '#12 345']) {
      expect(parseHexColor(bad), isNull, reason: bad);
    }
  });

  test('writes uppercase hex without alpha, and reads it back', () {
    expect(hexOf(const Color(0xFF0c386a)), '#0C386A');
    expect(hexOf(const Color(0xFF000000)), '#000000');
    expect(
      parseHexColor(hexOf(const Color(0xFF3A0F55))),
      const Color(0xFF3A0F55),
    );
  });
}
