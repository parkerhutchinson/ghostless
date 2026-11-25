// Checks the orgs migration's rules on a real Supabase project: that each
// person reaches exactly their own orgs' data, and that only the right
// roles can change orgs and members.
//
// Needs a TEST project (never the live one: it creates and deletes users)
// with the migrations applied (`supabase db push`), and:
//
//   SUPABASE_TEST_URL=https://<ref>.supabase.co
//   SUPABASE_TEST_PUBLISHABLE_KEY=sb_publishable_...   (or the anon key)
//   SUPABASE_TEST_SECRET_KEY=sb_secret_...             (or service_role)
//
//   flutter test test/supabase/orgs_rls_test.dart
//
// Skipped without them. Email + password sign-in must be enabled on the
// test project (it is by default); the users are made already confirmed.
@Tags(['supabase'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

final _env = Platform.environment;

/// The project URL, also from the database host (`db.<ref>.supabase.co`)
/// or without https://.
final _url = switch (_env['SUPABASE_TEST_URL']?.trim()) {
  null || '' => null,
  final raw => () {
    var host = raw
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/+$'), '');
    if (host.startsWith('db.')) host = host.substring(3);
    return 'https://$host';
  }(),
};
final _publishable = _env['SUPABASE_TEST_PUBLISHABLE_KEY'];
final _secret = _env['SUPABASE_TEST_SECRET_KEY'];
final _skip = _url == null || _publishable == null || _secret == null
    ? 'Set SUPABASE_TEST_URL, SUPABASE_TEST_PUBLISHABLE_KEY and '
          'SUPABASE_TEST_SECRET_KEY to run against a test project.'
    : null;

const _bucket = 'codename';

Map<String, String> _keyHeaders(String key) => {
  'apikey': key,
  if (key.startsWith('eyJ')) 'Authorization': 'Bearer $key',
};

/// A signed-in test person.
class Person {
  Person(this.id, this.email, this.token);
  final String id, email, token;

  Map<String, String> get _headers => {
    'apikey': _publishable!,
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Uri _rest(String path) => Uri.parse('$_url/rest/v1/$path');

  /// Rows of [table] this person can see, filtered by [query] (PostgREST).
  Future<List<Map<String, Object?>>> select(
    String table, [
    String query = '',
  ]) async {
    final r = await http.get(
      _rest('$table?select=*${query.isEmpty ? '' : '&$query'}'),
      headers: _headers,
    );
    expect(r.statusCode, 200, reason: 'select $table: ${r.body}');
    return [
      for (final row in jsonDecode(r.body) as List) row as Map<String, Object?>,
    ];
  }

  /// Inserts [row]; the HTTP status (201 ok, 403/401 refused).
  Future<int> insert(String table, Map<String, Object?> row) async {
    final r = await http.post(
      _rest(table),
      headers: {..._headers, 'Prefer': 'return=minimal'},
      body: jsonEncode(row),
    );
    return r.statusCode;
  }

  /// Updates rows matching [query]; how many it changed.
  Future<int> update(
    String table,
    String query,
    Map<String, Object?> values,
  ) async {
    final r = await http.patch(
      _rest('$table?$query'),
      headers: {..._headers, 'Prefer': 'return=representation'},
      body: jsonEncode(values),
    );
    if (r.statusCode != 200) return 0;
    return (jsonDecode(r.body) as List).length;
  }

  /// Calls a function; its result, or throws [RpcError].
  Future<Object?> rpc(String name, Map<String, Object?> args) async {
    final r = await http.post(
      _rest('rpc/$name'),
      headers: _headers,
      body: jsonEncode(args),
    );
    if (r.statusCode >= 300) throw RpcError(name, r.statusCode, r.body);
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  Future<int> upload(String path, String text) async {
    final r = await http.post(
      Uri.parse('$_url/storage/v1/object/$_bucket/$path'),
      headers: {
        'apikey': _publishable!,
        'Authorization': 'Bearer $token',
        'Content-Type': 'text/plain',
        'x-upsert': 'true',
      },
      body: text,
    );
    return r.statusCode;
  }

  Future<int> download(String path) async {
    final r = await http.get(
      Uri.parse('$_url/storage/v1/object/authenticated/$_bucket/$path'),
      headers: {'apikey': _publishable!, 'Authorization': 'Bearer $token'},
    );
    return r.statusCode;
  }
}

class RpcError implements Exception {
  RpcError(this.name, this.status, this.body);
  final String name, body;
  final int status;
  @override
  String toString() => 'rpc $name ($status): $body';
}

Matcher refusedWith(String text) =>
    throwsA(isA<RpcError>().having((e) => e.body, 'body', contains(text)));

void main() {
  final run = Random().nextInt(1 << 32).toRadixString(36);
  // The org's own domain (A claims it), and an unrelated one.
  final orgDomain = 'acme-$run.example.com';
  final otherDomain = 'elsewhere-$run.example.com';
  final createdUsers = <String>[];
  final createdOrgs = <String>{};

  Future<Person> signUp(String email) async {
    const password = 'Test-password-123!';
    final made = await http.post(
      Uri.parse('$_url/auth/v1/admin/users'),
      headers: {..._keyHeaders(_secret!), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );
    expect(made.statusCode, 200, reason: 'create $email: ${made.body}');
    final id = (jsonDecode(made.body) as Map)['id'] as String;
    createdUsers.add(id);
    final signedIn = await http.post(
      Uri.parse('$_url/auth/v1/token?grant_type=password'),
      headers: {'apikey': _publishable!, 'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    expect(signedIn.statusCode, 200, reason: 'sign in: ${signedIn.body}');
    return Person(
      id,
      email,
      (jsonDecode(signedIn.body) as Map)['access_token'] as String,
    );
  }

  late Person a, b, c, outsider;
  late String aSpace, bSpace, business;

  setUpAll(() async {
    if (_skip != null) return;
    // The hosted bucket (made by hand on the live project).
    await http.post(
      Uri.parse('$_url/storage/v1/bucket'),
      headers: {..._keyHeaders(_secret!), 'Content-Type': 'application/json'},
      body: jsonEncode({'id': _bucket, 'name': _bucket, 'public': false}),
    );
    a = await signUp('owner@$orgDomain');
    b = await signUp('invited-$run@$otherDomain');
    c = await signUp('colleague@$orgDomain');
    outsider = await signUp('outsider-$run@$otherDomain');
    aSpace = await a.rpc('ensure_personal_space', {
      'space_name': 'A',
      'new_profile': 'a-personal',
    }) as String;
    bSpace = await b.rpc('ensure_personal_space', {
      'space_name': 'B',
      'new_profile': 'b-personal',
    }) as String;
    business = await a.rpc('create_business_org', {
      'org_name': 'Acme $run',
      'new_profile': 'a-work',
    }) as String;
    createdOrgs.addAll([aSpace, bSpace, business]);
  });

  final uploaded = <String>[];

  tearDownAll(() async {
    if (_skip != null) return;
    // Files aren't deleted with their org.
    await http.delete(
      Uri.parse('$_url/storage/v1/object/$_bucket'),
      headers: {..._keyHeaders(_secret!), 'Content-Type': 'application/json'},
      body: jsonEncode({'prefixes': uploaded}),
    );
    // Orgs (and with them everything in them), then the users.
    if (createdOrgs.isNotEmpty) {
      await http.delete(
        Uri.parse('$_url/rest/v1/orgs?id=in.(${createdOrgs.join(',')})'),
        headers: _keyHeaders(_secret!),
      );
    }
    for (final id in createdUsers) {
      await http.delete(
        Uri.parse('$_url/auth/v1/admin/users/$id'),
        headers: _keyHeaders(_secret!),
      );
    }
  });

  group('personal spaces', skip: _skip, () {
    test('one per person, the same one every time', () async {
      expect(aSpace, isNot(bSpace));
      expect(
        await a.rpc('ensure_personal_space', {
          'space_name': 'again',
          'new_profile': 'x',
        }),
        aSpace,
      );
    });

    test("nobody reaches another person's space", () async {
      expect(
        await a.insert('projects', {
          'id': 'p-a-$run',
          'orgId': aSpace,
          'name': 'Private',
        }),
        201,
      );
      expect(await b.select('projects', 'id=eq.p-a-$run'), isEmpty);
      expect(
        await b.insert('projects', {
          'id': 'p-b-$run',
          'orgId': aSpace,
          'name': 'Sneaky',
        }),
        anyOf(401, 403),
      );
      expect(
        await b.update('projects', 'id=eq.p-a-$run', {'name': 'Hacked'}),
        0,
      );
      expect(await b.select('orgs', 'id=eq.$aSpace'), isEmpty);
    });

    test('records without an org are reachable by nobody', () async {
      expect(
        await a.insert('projects', {'id': 'p-none-$run', 'name': 'Loose'}),
        anyOf(401, 403),
      );
    });
  });

  group('business org', skip: _skip, () {
    test('one business org per person', () async {
      expect(
        a.rpc('create_business_org', {
          'org_name': 'Second',
          'new_profile': 'a-2',
        }),
        refusedWith('already belong'),
      );
    });

    test('joining needs an invite (or a claimed domain)', () async {
      expect(
        outsider.rpc('join_org', {'new_profile': 'o'}),
        refusedWith('no invite'),
      );
    });

    test(
      'an invited person joins as a member, and becomes the placeholder',
      () async {
        // A placeholder person (no login) with a task assigned to them.
        expect(
          await a.insert('profiles', {
            'id': 'placeholder-$run',
            'orgId': business,
            'name': 'Bea (not joined)',
          }),
          201,
        );
        await a.rpc('invite_member', {
          'org': business,
          'invitee_email': b.email.toUpperCase(),
          'member_role': 'member',
          'placeholder': 'placeholder-$run',
        });
        // B sees their invite; the outsider doesn't.
        expect(await b.select('org_invites'), hasLength(1));
        expect(await outsider.select('org_invites'), isEmpty);
        final joined =
            (await b.rpc('join_org', {'new_profile': 'b-work'}) as List).single
                as Map;
        expect(joined['org'], business);
        expect(joined['member_role'], 'member');
        expect(joined['profile'], 'placeholder-$run');
        expect(await b.select('orgs', 'id=eq.$business'), hasLength(1));
        // Both spaces, each their own.
        expect(
          await b.select('org_members', 'user_id=eq.${b.id}'),
          hasLength(2),
        );
      },
    );

    test("members see the org's work, not others' personal projects", () async {
      await a.insert('projects', {
        'id': 'shared-$run',
        'orgId': business,
        'name': 'Launch',
      });
      await a.insert('projects', {
        'id': 'a-own-$run',
        'orgId': business,
        'name': "A's personal",
        'ownerId': 'a-work',
      });
      await a.insert('tasks', {
        'id': 't-shared-$run',
        'orgId': business,
        'originId': 'shared-$run',
        'title': 'Ship',
      });
      await a.insert('tasks', {
        'id': 't-own-$run',
        'orgId': business,
        'originId': 'a-own-$run',
        'title': 'Private errand',
      });
      final projects = await b.select('projects', 'orgId=eq.$business');
      expect(projects.map((p) => p['id']), ['shared-$run']);
      final tasks = await b.select('tasks', 'orgId=eq.$business');
      expect(tasks.map((t) => t['id']), ['t-shared-$run']);
      expect(await outsider.select('tasks', 'orgId=eq.$business'), isEmpty);
      // B can't slip a task into A's personal project either.
      expect(
        await b.insert('tasks', {
          'id': 't-sneak-$run',
          'orgId': business,
          'originId': 'a-own-$run',
          'title': 'Peek',
        }),
        anyOf(401, 403),
      );
    });

    test('comments: written as yourself, hidden with their task', () async {
      expect(
        await b.insert('comments', {
          'id': 'c-b-$run',
          'orgId': business,
          'taskId': 't-shared-$run',
          'authorId': 'placeholder-$run',
          'body': 'On it',
        }),
        201,
      );
      expect(
        await b.insert('comments', {
          'id': 'c-forged-$run',
          'orgId': business,
          'taskId': 't-shared-$run',
          'authorId': 'a-work',
          'body': 'Pretending to be A',
        }),
        anyOf(401, 403),
      );
      await a.insert('comments', {
        'id': 'c-own-$run',
        'orgId': business,
        'taskId': 't-own-$run',
        'authorId': 'a-work',
        'body': 'Note to self',
      });
      final seen = await b.select('comments', 'orgId=eq.$business');
      expect(seen.map((c) => c['id']), ['c-b-$run']);
      // Only its author (or an owner/admin) edits a comment.
      expect(await b.update('comments', 'id=eq.c-own-$run', {'body': 'x'}), 0);
    });

    test('activity: only its recipient and whoever caused it', () async {
      expect(
        await a.insert('activity', {
          'id': 'act-$run',
          'orgId': business,
          'recipientId': 'placeholder-$run',
          'actorId': 'a-work',
          'kind': 'assigned',
          'taskId': 't-shared-$run',
        }),
        201,
      );
      expect(await b.select('activity', 'id=eq.act-$run'), hasLength(1));
      expect(await c.select('activity', 'id=eq.act-$run'), isEmpty);
      // Nobody writes activity between two other people.
      expect(
        await b.insert('activity', {
          'id': 'act-forged-$run',
          'orgId': business,
          'recipientId': 'a-work',
          'actorId': 'a-work',
          'kind': 'assigned',
        }),
        anyOf(401, 403),
      );
    });

    test('profiles: your own or placeholders, not colleagues\'', () async {
      expect(
        await b.update('profiles', 'id=eq.placeholder-$run', {'name': 'Bea'}),
        1,
      );
      await a.insert('profiles', {
        'id': 'a-work',
        'orgId': business,
        'name': 'Alex',
      });
      expect(await b.update('profiles', 'id=eq.a-work', {'name': 'Hacked'}), 0);
    });

    test('roles: members can\'t manage; admins invite members only', () async {
      expect(
        b.rpc('invite_member', {
          'org': business,
          'invitee_email': 'x-$run@$otherDomain',
        }),
        refusedWith('owner or admin'),
      );
      expect(
        b.rpc('change_role', {
          'org': business,
          'member': b.id,
          'member_role': 'admin',
        }),
        refusedWith('Only the owner'),
      );
      expect(
        b.rpc('remove_member', {'org': business, 'member': a.id}),
        refusedWith("can't remove"),
      );
      await a.rpc('change_role', {
        'org': business,
        'member': b.id,
        'member_role': 'admin',
      });
      expect(
        b.rpc('invite_member', {
          'org': business,
          'invitee_email': 'boss-$run@$otherDomain',
          'member_role': 'admin',
        }),
        refusedWith('Only the owner can invite admins'),
      );
      await b.rpc('invite_member', {
        'org': business,
        'invitee_email': 'helper-$run@$otherDomain',
      });
      // An admin can't remove the owner.
      expect(
        b.rpc('remove_member', {'org': business, 'member': a.id}),
        refusedWith("can't remove"),
      );
    });

    test("where the data lives: the owner's alone", () async {
      expect(
        await a.insert('org_connections', {
          'org_id': business,
          'database': {'kind': 'postgres', 'host': 'db.acme.example'},
        }),
        201,
      );
      expect(await a.select('org_connections'), hasLength(1));
      // Even an admin sees nothing, and can't write it.
      expect(await b.select('org_connections'), isEmpty);
      expect(
        await b.update('org_connections', 'org_id=eq.$business', {
          'database': {'host': 'evil.example'},
        }),
        0,
      );
      // Each member's own login: theirs and the owner's to read.
      expect(
        await a.insert('member_credentials', {
          'org_id': business,
          'user_id': b.id,
          'database': {'username': 'bea', 'password': 'secret'},
        }),
        201,
      );
      expect(await b.select('member_credentials'), hasLength(1));
      expect(
        await b.insert('member_credentials', {
          'org_id': business,
          'user_id': b.id,
          'database': {'username': 'me', 'password': 'mine'},
        }),
        anyOf(401, 403, 409),
      );
    });

    test('a claimed domain lets colleagues join; shared providers can\'t be claimed', () async {
      expect(
        a.rpc('claim_domain', {'org': business, 'new_domain': otherDomain}),
        refusedWith('your own email'),
      );
      await a.rpc('claim_domain', {'org': business, 'new_domain': orgDomain});
      final joined =
          (await c.rpc('join_org', {'new_profile': 'c-work'}) as List).single
              as Map;
      expect(joined['org'], business);
      expect(joined['member_role'], 'member');
      // Members can't claim domains.
      expect(
        c.rpc('claim_domain', {'org': business, 'new_domain': orgDomain}),
        refusedWith('Only the owner'),
      );
    });

    test(
      'files: members reach their org\'s folder, nobody else does',
      () async {
        uploaded.addAll([
          '$business/tasks/hello-$run.txt',
          '$business/tasks/evil-$run.txt',
          '$aSpace/tasks/mine-$run.txt',
        ]);
        expect(await a.upload('$business/tasks/hello-$run.txt', 'hi'), 200);
        expect(await b.download('$business/tasks/hello-$run.txt'), 200);
        expect(
          await outsider.download('$business/tasks/hello-$run.txt'),
          anyOf(400, 403, 404),
        );
        expect(
          await outsider.upload('$business/tasks/evil-$run.txt', 'x'),
          anyOf(400, 403),
        );
        expect(await a.upload('$aSpace/tasks/mine-$run.txt', 'mine'), 200);
        expect(
          await b.download('$aSpace/tasks/mine-$run.txt'),
          anyOf(400, 403, 404),
        );
      },
    );

    test('leaving and removal', () async {
      expect(
        a.rpc('leave_org', {'org': business}),
        refusedWith('Hand the org'),
      );
      await b.rpc('remove_member', {'org': business, 'member': c.id});
      expect(await c.select('tasks', 'orgId=eq.$business'), isEmpty);
      await b.rpc('leave_org', {'org': business});
      expect(await b.select('projects', 'orgId=eq.$business'), isEmpty);
      // B still has their personal space.
      expect(await b.select('orgs', 'id=eq.$bSpace'), hasLength(1));
    });
  });
}
