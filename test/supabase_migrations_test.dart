import 'dart:io';

import 'package:codename/sync/app_schema.dart';
import 'package:codename/sync/compatibility.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

/// The tables the Supabase migrations (`supabase/migrations/*.sql`, in
/// order) end up with: table → column → SQL type. Only reads the
/// statements the migrations use: `create table if not exists`,
/// `alter table ... add column if not exists`.
Map<String, Map<String, String>> migratedTables() {
  final files =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final tables = <String, Map<String, String>>{};
  final column = RegExp(
    r'^\s*(?:add column if not exists\s+)?"?(\w+)"?\s+'
    r'(text|integer|double precision|jsonb|timestamptz)\b',
    caseSensitive: false,
  );
  for (final file in files) {
    // Comments out, then statement by statement.
    final sql = file.readAsStringSync().replaceAll(RegExp(r'--[^\n]*'), '');
    for (final statement in sql.split(';')) {
      final head = RegExp(
        r'(?:create table if not exists|alter table)\s+public\.(\w+)',
        caseSensitive: false,
      ).firstMatch(statement);
      if (head == null) continue;
      final columns = tables.putIfAbsent(head.group(1)!, () => {});
      // Inside "create table (...)" or after "alter table x": one column
      // per comma-separated part.
      final body = statement.substring(head.end).replaceAll(RegExp(r'^\s*\('), '');
      for (final part in body.split(',')) {
        if (column.firstMatch(part) case final m?) {
          columns[m.group(1)!] = m.group(2)!.toLowerCase();
        }
      }
    }
  }
  return tables;
}

/// What `information_schema` calls a type written in the migrations.
String dataType(String sqlType) =>
    sqlType == 'timestamptz' ? 'timestamp with time zone' : sqlType;

void main() {
  final tables = migratedTables();
  const dialect = PostgresDialect();
  // Sync's own columns: not app fields. "orgId" is the org a record
  // belongs to (set by sync, not the models).
  const system = {'id', 'updated_at', 'deleted_at', 'orgId'};

  test('every synced collection has a table with the sync columns', () {
    for (final collection in appSchema.keys) {
      final columns = tables[collection];
      expect(columns, isNotNull, reason: 'no table for "$collection"');
      expect(columns!['id'], 'text', reason: '$collection.id');
      expect(columns['updated_at'], 'timestamptz');
      expect(columns['deleted_at'], 'timestamptz');
      expect(columns['orgId'], 'text', reason: '$collection."orgId"');
    }
  });

  test("every field has a column of a type that holds the app's values", () {
    for (final MapEntry(key: collection, value: fields) in appSchema.entries) {
      final columns = tables[collection]!;
      for (final MapEntry(key: name, value: kind) in fields.entries) {
        final type = columns[name];
        expect(type, isNotNull, reason: 'missing $collection."$name"');
        final field = FieldSchema(
          dialect.kindOf(dataType(type!)),
          nativeType: type,
        );
        expect(
          fits(kind, field, false),
          isTrue,
          reason: '$collection."$name" is $type; needs ${kind.description}',
        );
      }
    }
  });

  test('no columns the app has no field for', () {
    for (final MapEntry(key: collection, value: columns) in tables.entries) {
      // Orgs, members and the like aren't synced records.
      final fields = appSchema[collection];
      if (fields == null) continue;
      for (final name in columns.keys) {
        expect(
          system.contains(name) || fields.containsKey(name),
          isTrue,
          reason: '$collection."$name"',
        );
      }
    }
  });

  test('row level security is on for every table', () {
    final sql = [
      for (final f in Directory('supabase/migrations').listSync())
        if (f is File) f.readAsStringSync().toLowerCase(),
    ].join('\n');
    for (final collection in {...appSchema.keys, ...tables.keys}) {
      expect(
        sql.contains(
          'alter table public.$collection enable row level security',
        ),
        isTrue,
        reason: collection,
      );
    }
  });
}
