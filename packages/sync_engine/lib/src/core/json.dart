import 'dart:convert';
import 'dart:typed_data';

import 'change.dart';

/// JSON-encodes values backends commonly return (DateTime, bytes, etc.).
String encodeJson(Object? value) =>
    jsonEncode(value, toEncodable: _toEncodable);

Object? _toEncodable(Object? value) => switch (value) {
  DateTime() => value.toUtc().toIso8601String(),
  Uint8List() => base64Encode(value),
  _ => value.toString(),
};

/// A short, stable hash of a change's content (key order doesn't matter).
///
/// Two-way sync stores the fingerprint of every record it writes, so when
/// that write comes back on the next pull it is recognised and skipped.
String fingerprint(Change change) {
  if (change.isDelete) return 'deleted';
  final canonical = encodeJson(_sortKeys(change.data));
  // FNV-1a, 64-bit: no crypto needed, only change detection.
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(canonical)) {
    hash ^= byte;
    hash *= 0x100000001b3; // wraps at 64 bits on the Dart VM
  }
  return hash.toUnsigned(64).toRadixString(16);
}

Object? _sortKeys(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.map((k) => '$k').toList()..sort())
      key: _sortKeys(value[key]),
  },
  List() => value.map(_sortKeys).toList(),
  _ => value,
};
