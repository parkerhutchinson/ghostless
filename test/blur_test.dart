import 'dart:typed_data';

import 'package:codename/widgets/blur.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List image(int w, int h, int Function(int x, int y) red) =>
      Uint8List(w * h * 4)..setAll(0, [
        for (var y = 0; y < h; y++)
          for (var x = 0; x < w; x++) ...[red(x, y), 0, 0, 255],
      ]);
  int redAt(Uint8List p, int w, int x, int y) => p[(y * w + x) * 4];

  test('a flat image stays the same', () {
    final p = image(8, 6, (_, _) => 120);
    boxBlurRgba(p, 8, 6, 2);
    expect(p.toSet(), {120, 0, 255});
  });

  test('a sharp edge becomes a smooth ramp', () {
    final p = image(40, 3, (x, _) => x < 20 ? 0 : 255);
    boxBlurRgba(p, 40, 3, 3);
    final row = [for (var x = 0; x < 40; x++) redAt(p, 40, x, 1)];
    expect(row.first, 0);
    expect(row.last, 255);
    for (var x = 1; x < 40; x++) {
      expect(row[x], greaterThanOrEqualTo(row[x - 1]), reason: 'x=$x');
    }
    expect(row[19], inInclusiveRange(80, 175), reason: 'mid-grey at edge');
  });

  test('a bright dot spreads both ways, alpha untouched', () {
    final p = image(21, 21, (x, y) => x == 10 && y == 10 ? 255 : 0);
    boxBlurRgba(p, 21, 21, 1);
    expect(redAt(p, 21, 10, 10), lessThan(255));
    expect(redAt(p, 21, 11, 10), greaterThan(0));
    expect(redAt(p, 21, 10, 11), greaterThan(0));
    expect(p[3], 255);
  });

  test('a zero radius or empty image does nothing', () {
    final p = image(3, 3, (x, _) => x * 50);
    final before = Uint8List.fromList(p);
    boxBlurRgba(p, 3, 3, 0);
    expect(p, before);
    boxBlurRgba(Uint8List(0), 0, 0, 3);
  });
}
