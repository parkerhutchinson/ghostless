import 'dart:convert';
import 'dart:typed_data';

import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_logo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkLogoSize', () {
    test('accepts square images up to 256', () {
      expect(checkLogoSize(256, 256), isNull);
      expect(checkLogoSize(32, 32), isNull);
    });
    test('turns down non-square and oversized images', () {
      expect(checkLogoSize(256, 200), contains('square'));
      expect(checkLogoSize(512, 512), contains('at most 256 × 256'));
      expect(checkLogoSize(0, 0), isNotNull);
    });
  });

  group('svgSize', () {
    test('reads the viewBox first', () {
      expect(
        svgSize('<svg width="10" height="20" viewBox="0 0 24 24"></svg>'),
        (24.0, 24.0),
      );
      expect(svgSize("<svg viewBox='0,0,100,50'/>"), (100.0, 50.0));
    });
    test('falls back to width and height', () {
      expect(svgSize('<svg width="64px" height="64px"></svg>'), (64.0, 64.0));
    });
    test('null without a size', () {
      expect(svgSize('<svg></svg>'), isNull);
      expect(svgSize('not an svg'), isNull);
    });
  });

  group('readLogo (SVG)', () {
    Uint8List svg(String s) => Uint8List.fromList(utf8.encode(s));

    test('accepts a square SVG of any size', () async {
      final logo = await readLogo(
        svg('<svg viewBox="0 0 1000 1000"></svg>'),
        'Logo.SVG',
      );
      expect(logo.isSvg, isTrue);
    });
    test('turns down a wide SVG or one with no size', () async {
      await expectLater(
        readLogo(svg('<svg viewBox="0 0 200 100"></svg>'), 'a.svg'),
        throwsA(isA<LogoException>()),
      );
      await expectLater(
        readLogo(svg('<svg></svg>'), 'a.svg'),
        throwsA(isA<LogoException>()),
      );
    });
    test('turns down a file over the size limit', () async {
      await expectLater(
        readLogo(Uint8List(maxLogoBytes + 1), 'a.png'),
        throwsA(isA<LogoException>()),
      );
    });
  });

  test('a project keeps its logo through JSON; copyWith can clear it', () {
    final logo = ProjectLogo(
      bytes: Uint8List.fromList([1, 2, 3]),
      isSvg: true,
    );
    final p = Project(
      id: 'p',
      name: 'Acme',
      logo: logo,
      createdAt: DateTime.utc(2026),
    );
    final back = Project.fromJson('p', p.toJson());
    expect(back.logo!.bytes, [1, 2, 3]);
    expect(back.logo!.isSvg, isTrue);
    expect(
      identical(Project.fromJson('p', p.toJson()).logo, back.logo),
      isTrue,
      reason: 'same data, same object: no redraw',
    );
    expect(back.copyWith(name: 'X').logo, same(back.logo));
    expect(back.copyWith(logo: null).logo, isNull);
    expect(Project.fromJson('p', {'name': 'No logo'}).logo, isNull);
  });
}
