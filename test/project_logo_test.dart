import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:codename/projects/project.dart';
import 'package:codename/projects/project_logo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkLogoSize', () {
    test('accepts square images of any size', () {
      expect(checkLogoSize(256, 256), isNull);
      expect(checkLogoSize(32, 32), isNull);
      expect(checkLogoSize(2048, 2048), isNull);
    });
    test('turns down non-square images', () {
      expect(checkLogoSize(256, 200), contains('square'));
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
    test('turns down files over the size limits', () async {
      await expectLater(
        readLogo(Uint8List(maxLogoBytes + 1), 'a.svg'),
        throwsA(isA<LogoException>()),
      );
      await expectLater(
        readLogo(Uint8List(maxLogoFileBytes + 1), 'a.png'),
        throwsA(isA<LogoException>()),
      );
    });
  });

  group('readLogo (image)', () {
    /// A [size] × [height] PNG, filled red.
    Future<Uint8List> png(int size, [int? height]) async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        ui.Rect.fromLTWH(0, 0, size.toDouble(), (height ?? size).toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      final image = await recorder.endRecording().toImage(size, height ?? size);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    Future<(int, int)> sizeOf(Uint8List bytes) async {
      final frame = await (await ui.instantiateImageCodec(bytes))
          .getNextFrame();
      return (frame.image.width, frame.image.height);
    }

    testWidgets('a big square image is scaled down to $maxLogoSize', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final logo = await readLogo(await png(1024), 'big.png');
        expect(logo.isSvg, isFalse);
        expect(await sizeOf(logo.bytes), (maxLogoSize, maxLogoSize));
      });
    });

    testWidgets('a small one is kept as it is', (tester) async {
      await tester.runAsync(() async {
        final bytes = await png(64);
        expect((await readLogo(bytes, 'small.png')).bytes, same(bytes));
      });
    });

    testWidgets('a wide one is turned down', (tester) async {
      await tester.runAsync(() async {
        await expectLater(
          readLogo(await png(400, 300), 'wide.png'),
          throwsA(isA<LogoException>()),
        );
      });
    });
  });

  test('a project keeps its logo through JSON; copyWith can clear it', () {
    final logo = ProjectLogo(bytes: Uint8List.fromList([1, 2, 3]), isSvg: true);
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
