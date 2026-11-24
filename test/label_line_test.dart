import 'package:codename/tasks/label_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // "+N" is 20 wide, whatever N.
  double more(int _) => 20;

  test('all fit: every chip, no +N', () {
    expect(chipsThatFit([30, 30, 30], 98, more), 3); // 30*3 + 4*2 = 98
  });

  test('not all fit: as many as leave room for +N', () {
    // 30 + 4 + 30 = 64, + 4 + 20 = 88 ≤ 90; a third wouldn't fit.
    expect(chipsThatFit([30, 30, 30, 30], 90, more), 2);
  });

  test('always at least one, cut short', () {
    expect(chipsThatFit([200, 30], 90, more), 1);
    expect(chipsThatFit([], 90, more), 0);
  });
}
