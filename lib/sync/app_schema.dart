import 'dart:convert';

/// What kind of value one of the app's record fields holds. Records are
/// JSON: dates and times are ISO-8601 strings.
enum ValueKind {
  string('text'),

  /// An ISO-8601 date and time (a timestamp column works too).
  timestamp('a date and time'),
  number('a number'),
  stringList('a list of text'),
  objectList('a list of objects'),
  object('an object');

  const ValueKind(this.description);

  /// For messages: "tags should be a list of text".
  final String description;

  /// Lists and objects: stored as JSON.
  bool get isStructured =>
      this != string && this != timestamp && this != number;

  bool accepts(Object? value) => switch (this) {
    string || timestamp => value is String,
    number => value is num,
    stringList => value is List && value.every((v) => v is String),
    objectList => value is List && value.every((v) => v is Map),
    object => value is Map,
  };
}

/// The records the app syncs: collection → field → kind. Mirrors the
/// models' `toJson` (Project, Task, Profile, Activity); keep it in step when
/// a model gains a field. A database the app connects to needs these
/// fields, named exactly so.
const appSchema = <String, Map<String, ValueKind>>{
  'projects': {
    'name': ValueKind.string,
    'colorIndex': ValueKind.number,
    'order': ValueKind.number,
    'columns': ValueKind.objectList,
    'ownerId': ValueKind.string,
    'createdAt': ValueKind.timestamp,
  },
  'tasks': {
    'title': ValueKind.string,
    'description': ValueKind.string,
    'status': ValueKind.string,
    'order': ValueKind.number,
    'tags': ValueKind.stringList,
    'images': ValueKind.stringList,
    'originId': ValueKind.string,
    'projectIds': ValueKind.stringList,
    'dueDate': ValueKind.string,
    'dueTime': ValueKind.string,
    'completedIn': ValueKind.stringList,
    'placements': ValueKind.object,
    'subtasks': ValueKind.objectList,
    'assigneeId': ValueKind.string,
    'createdAt': ValueKind.timestamp,
  },
  'profiles': {
    'name': ValueKind.string,
    'department': ValueKind.string,
    'jobTitle': ValueKind.string,
    'description': ValueKind.string,
    'imageFile': ValueKind.string,
    'personalProjectId': ValueKind.string,
    'theme': ValueKind.object,
    'createdAt': ValueKind.timestamp,
  },
  'activity': {
    'recipientId': ValueKind.string,
    'actorId': ValueKind.string,
    'taskId': ValueKind.string,
    'taskTitle': ValueKind.string,
    'kind': ValueKind.string,
    'changes': ValueKind.stringList,
    'dueAt': ValueKind.timestamp,
    'createdAt': ValueKind.timestamp,
    'readAt': ValueKind.timestamp,
  },
};

/// A record coming in from a database, in the app's shapes: timestamps as
/// ISO strings, JSON text decoded where the app expects a list or object
/// (SQL stores those as JSON), and whole numbers kept as numbers.
Map<String, Object?> fromRemote(String collection, Map<String, Object?> data) {
  final fields = appSchema[collection] ?? const {};
  return {
    for (final MapEntry(:key, :value) in data.entries)
      key: _coerce(fields[key], value),
  };
}

Object? _coerce(ValueKind? kind, Object? value) => switch ((kind, value)) {
  (_, final DateTime d) => d.toUtc().toIso8601String(),
  (final k?, final String text) when k.isStructured => _tryDecode(text),
  _ => value,
};

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// Field values in [data] the app can't read, by field: wrong types would
/// make a model's `fromJson` throw. Nulls and unknown fields are fine (the
/// models fill in defaults and ignore extras).
Map<String, ValueKind> invalidFields(
  String collection,
  Map<String, Object?> data,
) => {
  for (final MapEntry(:key, :value) in (appSchema[collection] ?? {}).entries)
    if (data[key] != null && !value.accepts(data[key])) key: value,
};

/// [data] without fields the app can't read, so a bad value from a
/// database falls back to the model's default instead of breaking the app.
Map<String, Object?> withoutInvalidFields(
  String collection,
  Map<String, Object?> data,
) {
  final bad = invalidFields(collection, data);
  if (bad.isEmpty) return data;
  return {...data}..removeWhere((key, _) => bad.containsKey(key));
}

/// A record going out to an SQL database: lists and objects as JSON text,
/// which both JSON and text columns accept (drivers would otherwise send a
/// list as an SQL array).
Map<String, Object?> toSql(Map<String, Object?> data) => {
  for (final MapEntry(:key, :value) in data.entries)
    key: value is List || value is Map ? jsonEncode(value) : value,
};
