import 'package:sync_engine/sync_engine.dart';

import 'app_schema.dart';

/// Fields the app sometimes leaves empty (null): a database must allow
/// that.
const optionalFields = <String, Set<String>>{
  'projects': {'ownerId', 'logo'},
  'tasks': {'dueDate', 'dueTime', 'assigneeId'},
  'profiles': {'imageFile', 'personalProjectId'},
  'activity': {'actorId', 'dueAt', 'readAt', 'dismissedAt'},
};

enum CheckLevel { passed, warning, error }

/// One finding from [checkCompatibility].
final class CheckResult {
  const CheckResult(this.level, this.message, {this.collection});
  final CheckLevel level;

  /// The collection it's about; null for the database as a whole.
  final String? collection;
  final String message;

  @override
  String toString() =>
      '${level.name}: ${collection == null ? '' : '$collection: '}$message';
}

final class CompatibilityReport {
  const CompatibilityReport(this.results, {this.softDeletes = const {}});

  final List<CheckResult> results;

  /// SQL tables with a `deleted_at` column, so deletes sync through them.
  final Set<String> softDeletes;

  /// Nothing stops syncing (warnings are fine).
  bool get compatible => results.every((r) => r.level != CheckLevel.error);

  Iterable<CheckResult> get errors =>
      results.where((r) => r.level == CheckLevel.error);
}

/// The column/type/document type a collection is in [adapter]'s terms.
String collectionNoun(SyncAdapter adapter) => switch (adapter) {
  SanityAdapter() => 'document type',
  ContentfulAdapter() => 'content type',
  _ => 'table',
};

/// Checks whether [adapter]'s database will work with the app: that it
/// connects; that each synced collection exists with the app's fields and
/// value types (where the database has a schema); that the records already
/// in it can be read by the app; and that the credentials can write. Opens
/// and closes [adapter].
///
/// [jsonInText]: lists and objects are written as JSON text (SQL), so text
/// columns can hold them.
Future<CompatibilityReport> checkCompatibility(
  SyncAdapter adapter, {
  bool jsonInText = false,
  int sampleSize = 50,
}) async {
  final results = <CheckResult>[];
  final softDeletes = <String>{};
  try {
    await adapter.open();
  } catch (e) {
    return CompatibilityReport([
      CheckResult(CheckLevel.error, 'Couldn’t connect: ${_short(e)}'),
    ]);
  }
  final noun = collectionNoun(adapter);
  final inspector = adapter is SchemaInspector
      ? adapter as SchemaInspector
      : null;
  try {
    for (final collection in appSchema.keys) {
      final found = <CheckResult>[];
      void add(CheckLevel level, String message) =>
          found.add(CheckResult(level, message, collection: collection));

      // Structure.
      if (inspector != null && inspector.hasSchema) {
        try {
          final schema = await inspector.describe(collection);
          if (schema == null) {
            add(CheckLevel.error, 'There’s no $noun named “$collection”.');
            results.addAll(found);
            continue;
          }
          _compareFields(collection, schema, jsonInText, add);
          if (adapter is PostgresAdapter || adapter is MySqlAdapter) {
            if (schema.fields['deleted_at']?.kind == FieldKind.timestamp) {
              softDeletes.add(collection);
            } else {
              add(
                CheckLevel.warning,
                'Without a “deleted_at” timestamp column, deleting '
                'something on one Mac won’t remove it on others.',
              );
            }
          }
        } catch (e) {
          add(CheckLevel.error, 'Couldn’t read its structure: ${_short(e)}');
        }
      }

      // The records already there.
      try {
        final page = await adapter.pull(collection, limit: sampleSize);
        final records = [
          for (final c in page.changes)
            if (c.data case final data?) fromRemote(collection, data),
        ];
        final bad = <String, ValueKind>{};
        var badRecords = 0;
        for (final r in records) {
          final invalid = invalidFields(collection, r);
          if (invalid.isNotEmpty) badRecords++;
          bad.addAll(invalid);
        }
        if (badRecords > 0) {
          add(
            CheckLevel.error,
            '$badRecords of ${records.length} records have values the app '
            'can’t read: ${[for (final MapEntry(:key, :value) in bad.entries) '“$key” should be ${value.description}'].join(', ')}.',
          );
        } else if (found.every((r) => r.level != CheckLevel.error)) {
          add(
            CheckLevel.passed,
            records.isEmpty
                ? 'Ready (empty)'
                : 'Ready (${records.length}${page.hasMore ? '+' : ''} '
                      'record${records.length == 1 ? '' : 's'} checked)',
          );
        }
      } catch (e) {
        add(CheckLevel.error, 'Couldn’t read it: ${_short(e)}');
      }

      // Permission to write.
      if (inspector != null) {
        try {
          if (await inspector.canWrite(collection) == false) {
            add(CheckLevel.error, 'These credentials can’t write to it.');
          }
        } catch (e) {
          add(CheckLevel.warning, 'Couldn’t check write access: ${_short(e)}');
        }
      }
      // Errors first, then warnings, then the all-clear.
      found.sort((a, b) => b.level.index.compareTo(a.level.index));
      results.addAll(found);
    }
    if (!adapter.capabilities.reportsDeletes) {
      results.add(
        const CheckResult(
          CheckLevel.warning,
          'This kind of database doesn’t report deletions, so deleting '
          'something on one Mac won’t remove it on others.',
        ),
      );
    }
  } finally {
    try {
      await adapter.close();
    } catch (_) {}
  }
  return CompatibilityReport(results, softDeletes: softDeletes);
}

void _compareFields(
  String collection,
  CollectionSchema schema,
  bool jsonInText,
  void Function(CheckLevel, String) add,
) {
  final expected = appSchema[collection]!;
  final optional = optionalFields[collection] ?? const {};
  for (final MapEntry(key: name, value: kind) in expected.entries) {
    final field = schema.fields[name];
    if (field == null) {
      add(CheckLevel.error, 'Missing the “$name” field (${kind.description}).');
    } else if (!fits(kind, field, jsonInText || schema.jsonInText)) {
      add(
        CheckLevel.error,
        '“$name” is ${field.nativeType}; it needs to hold ${kind.description}.',
      );
    } else if (optional.contains(name) && field.required) {
      add(
        CheckLevel.error,
        '“$name” can’t be left empty there, but the app leaves it empty '
        'sometimes.',
      );
    }
  }
  for (final MapEntry(:key, :value) in schema.fields.entries) {
    if (!expected.containsKey(key) && key != 'deleted_at' && value.required) {
      add(
        CheckLevel.error,
        '“$key” is required there, but the app has no such field.',
      );
    }
  }
  for (final note in schema.notes) {
    add(
      note.level == SchemaNoteLevel.error
          ? CheckLevel.error
          : CheckLevel.warning,
      note.message,
    );
  }
}

/// Whether a backend [field] can hold the app's [kind] of value.
bool fits(ValueKind kind, FieldSchema field, bool jsonInText) =>
    switch ((kind, field.kind)) {
      (ValueKind.string, FieldKind.string) => true,
      (ValueKind.timestamp, FieldKind.string || FieldKind.timestamp) => true,
      (ValueKind.number, FieldKind.number) => true,
      (ValueKind.stringList, FieldKind.stringList || FieldKind.json) => true,
      (ValueKind.objectList || ValueKind.object, FieldKind.json) => true,
      (_, FieldKind.string) when kind.isStructured => jsonInText,
      _ => false,
    };

/// An error's message without the exception class noise, kept short.
String _short(Object e) {
  final text = switch (e) {
    SyncAdapterException(:final message) => message,
    _ => '$e',
  }.replaceFirst(RegExp(r'^\w*(Exception|Error):\s*'), '');
  return text.length > 240 ? '${text.substring(0, 240)}…' : text;
}
