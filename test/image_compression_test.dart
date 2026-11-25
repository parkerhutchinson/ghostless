import 'dart:math';
import 'dart:typed_data';

import 'dart:io';

import 'package:codename/tasks/image_compression.dart';
import 'package:codename/tasks/task_repository.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A "photo": a gradient with noise, which PNG can't squeeze much (as
/// with a real photo) but JPEG can.
img.Image photo(int w, int h, {bool alpha = false}) {
  final random = Random(1);
  final image = img.Image(width: w, height: h, numChannels: alpha ? 4 : 3);
  for (final p in image) {
    int noisy(int v) => (v + random.nextInt(24)).clamp(0, 255);
    p
      ..r = noisy(p.x * 200 ~/ w)
      ..g = noisy(p.y * 200 ~/ h)
      ..b = noisy(120);
    if (alpha) p.a = p.x < w ~/ 2 ? 0 : 255;
  }
  return image;
}

void main() {
  test('a big opaque PNG becomes a smaller JPEG, at most 2048 wide', () {
    final png = img.encodePng(photo(3000, 1500));
    final out = compressImageNow(png, 'png');
    expect(out.extension, 'jpg');
    expect(out.bytes.length, lessThan(png.length));
    final back = img.decodeImage(Uint8List.fromList(out.bytes))!;
    expect((back.width, back.height), (maxImageSide, 1024));
  });

  test('a tall one is limited by its height', () {
    final jpg = img.encodeJpg(photo(1200, 2400), quality: 100);
    final back = img.decodeImage(
      Uint8List.fromList(compressImageNow(jpg, 'jpg').bytes),
    )!;
    expect((back.width, back.height), (1024, maxImageSide));
  });

  test('see-through images stay PNG', () {
    final png = img.encodePng(photo(2600, 1300, alpha: true), level: 0);
    final out = compressImageNow(png, 'png');
    expect(out.extension, 'png');
    final back = img.decodeImage(Uint8List.fromList(out.bytes))!;
    expect(back.width, maxImageSide);
  });

  test('kept as is when not smaller, not an image, or animated', () {
    final small = img.encodeJpg(photo(40, 40), quality: 50);
    expect(identical(compressImageNow(small, 'jpg').bytes, small), isTrue);
    final pdf = [0x25, 0x50, 0x44, 0x46, 1, 2, 3];
    expect(compressImageNow(pdf, 'pdf').extension, 'pdf');
    expect(compressImageNow([1, 2, 3], 'png').bytes, [1, 2, 3]);
    final anim = img.Image(width: 300, height: 300)
      ..addFrame(img.Image(width: 300, height: 300));
    final gif = img.encodeGif(anim);
    expect(compressImageNow(gif, 'gif').extension, 'gif');
  });

  test('an attachment is named for its new type', () {
    expect(withExtensionOf('photo.png', 'x.jpg'), 'photo.jpg');
    expect(withExtensionOf('scan.JPEG', 'x.jpg'), 'scan.JPEG');
    expect(withExtensionOf('report.pdf', 'x.pdf'), 'report.pdf');
    expect(withExtensionOf('noext', 'x.jpg'), 'noext.jpg');
  });

  test('added images are stored smaller; duplicates copy them as is', () async {
    final dir = Directory.systemTemp.createTempSync('compress');
    final store = LocalStore.inMemory();
    final repo = TaskRepository(store, dir);
    final source = File('${dir.path}/big.png')
      ..writeAsBytesSync(img.encodePng(photo(2500, 1600)));
    final stored = await repo.addImage(source.path);
    expect(stored.endsWith('.jpg'), isTrue);
    expect(repo.imageFile(stored).lengthSync(), lessThan(source.lengthSync()));
    final task = repo.create(title: 'T', originId: 'p', images: [stored]);
    final copy = (await repo.duplicate(task.id))!;
    expect(
      repo.imageFile(copy.images.single).readAsBytesSync(),
      repo.imageFile(stored).readAsBytesSync(),
    );
    await store.close();
    dir.deleteSync(recursive: true);
  });
}
