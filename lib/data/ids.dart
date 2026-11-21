import 'dart:math';

final _random = Random.secure();

/// 128-bit random hex id: unique across devices, so records created offline
/// never collide when they sync.
String newId() => [
  for (var i = 0; i < 16; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();
