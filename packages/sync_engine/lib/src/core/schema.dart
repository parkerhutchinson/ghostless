/// What kind of value a backend field holds, as far as syncing cares.
enum FieldKind {
  /// Text (SQL `text`/`varchar`, Contentful `Symbol`/`Text`).
  string,

  /// Any number.
  number,

  boolean,

  /// A date or timestamp column. Records carry these as ISO-8601 strings.
  timestamp,

  /// Any JSON value: objects, lists, nested data (SQL `json`/`jsonb`,
  /// Contentful `Object`).
  json,

  /// A list of strings only (Contentful `Array` of `Symbol`).
  stringList,

  /// Something records can't be stored in (an SQL array, a binary column,
  /// a Contentful link).
  other,
}

/// One field of a collection, as the backend defines it.
final class FieldSchema {
  const FieldSchema(
    this.kind, {
    this.nullable = true,
    this.hasDefault = false,
    this.nativeType = '',
  });

  final FieldKind kind;

  /// Whether the field may be left empty (null).
  final bool nullable;

  /// Whether the backend fills the field in when a write leaves it out.
  final bool hasDefault;

  /// The backend's own name for the type (`jsonb`, `Symbol`…), for messages.
  final String nativeType;

  /// A write that leaves this field out fails.
  bool get required => !nullable && !hasDefault;
}

enum SchemaNoteLevel { error, warning }

/// Something an adapter noticed about a collection's structure beyond its
/// fields: a missing system column, a timestamp without enough precision.
final class SchemaNote {
  const SchemaNote(this.level, this.message);
  final SchemaNoteLevel level;
  final String message;

  @override
  String toString() => '${level.name}: $message';
}

/// A collection's structure in a backend: its data fields (system fields
/// such as ids and timestamps left out), and anything else worth knowing.
final class CollectionSchema {
  const CollectionSchema({
    required this.fields,
    this.notes = const [],
    this.jsonInText = false,
  });

  /// Data fields by name.
  final Map<String, FieldSchema> fields;

  final List<SchemaNote> notes;

  /// Lists and objects can be stored as JSON text in [FieldKind.string]
  /// fields (SQL: the adapter writes them as JSON strings).
  final bool jsonInText;
}

/// Optional interface for adapters that can describe a backend's structure
/// and check permissions before syncing, so an app can tell whether a
/// database will work before connecting to it.
abstract interface class SchemaInspector {
  /// False for schemaless backends (Sanity): [describe] then returns null,
  /// and only the data itself can be checked.
  bool get hasSchema;

  /// [collection]'s structure, or null when it doesn't exist (or the
  /// backend has no schema). Call after [SyncAdapter.open].
  Future<CollectionSchema?> describe(String collection);

  /// Whether the credentials may write to [collection]; null when that
  /// can't be told without writing.
  Future<bool?> canWrite(String collection);
}
