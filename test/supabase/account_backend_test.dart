// Checks SupabaseAuthBackend against a real (TEST) Supabase project: that
// a kept session resumes, a broken one is refused, and the personal space
// is made once. Emailing a code can't be automated, so the test signs in
// with a password instead (the session it gets is the same kind).
//
// Needs the same settings as orgs_rls_test.dart (.env.test); skipped
// without them.
@Tags(['supabase'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:codename/account/auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

final _env = Platform.environment;
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
    ? 'Set the SUPABASE_TEST_* settings (.env.test) to run.'
    : null;

Map<String, String> get _admin => {
  'apikey': _secret!,
  if (_secret!.startsWith('eyJ')) 'Authorization': 'Bearer $_secret',
  'Content-Type': 'application/json',
};

SupabaseClient _client() => SupabaseClient(
  _url!,
  _publishable!,
  authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
);

void main() {
  final run = Random().nextInt(1 << 32).toRadixString(36);
  final email = 'account-$run@example.com';
  const password = 'Test-password-123!';
  String? userId;
  String? space;

  setUpAll(() async {
    if (_skip != null) return;
    final made = await http.post(
      Uri.parse('$_url/auth/v1/admin/users'),
      headers: _admin,
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
      }),
    );
    expect(made.statusCode, 200, reason: made.body);
    userId = (jsonDecode(made.body) as Map)['id'] as String;
  });

  tearDownAll(() async {
    if (_skip != null) return;
    if (space != null) {
      await http.delete(
        Uri.parse('$_url/rest/v1/orgs?id=eq.$space'),
        headers: _admin,
      );
    }
    if (userId != null) {
      await http.delete(
        Uri.parse('$_url/auth/v1/admin/users/$userId'),
        headers: _admin,
      );
    }
  });

  test(
    'a kept session resumes; the personal space is made once',
    skip: _skip,
    () async {
      final client = _client();
      final signedIn = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final kept = jsonEncode(signedIn.session!.toJson());

      // A fresh launch: a new client, from the kept session alone.
      final backend = SupabaseAuthBackend(client: _client());
      final resumed = await backend.resume(kept);
      expect(resumed?.userId, userId);
      expect(resumed?.email, email);

      space = await backend.ensurePersonalSpace('Account test', 'p-$run');
      expect(space, isNotEmpty);
      expect(
        await backend.ensurePersonalSpace('Again', 'other'),
        space,
        reason: 'the same space every time',
      );

      await backend.signOut();
      client.dispose();
    },
  );

  test(
    'a broken session is refused (null), not an error',
    skip: _skip,
    () async {
      final backend = SupabaseAuthBackend(client: _client());
      // An access token that expired long ago (its expiry is read from
      // the token itself, without checking its signature), so the session
      // has to be refreshed, and the made-up refresh token is refused.
      String part(Map<String, Object?> json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final expired =
          '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
          '${part({'sub': '00000000-0000-0000-0000-000000000000', 'exp': 1})}.'
          'signature';
      final fake = jsonEncode({
        'access_token': expired,
        'token_type': 'bearer',
        'expires_in': 3600,
        'expires_at': 1,
        'refresh_token': 'not-a-real-token',
        'user': {
          'id': '00000000-0000-0000-0000-000000000000',
          'app_metadata': <String, Object?>{},
          'user_metadata': <String, Object?>{},
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
        },
      });
      expect(await backend.resume(fake), isNull);
    },
  );

  test('a wrong code says so', skip: _skip, () async {
    final backend = SupabaseAuthBackend(client: _client());
    await expectLater(
      backend.verifyCode(email, '000000'),
      throwsA(isA<AuthProblem>().having((e) => e.offline, 'offline', false)),
    );
  });
}
