import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'hosted_service.dart';

/// A signed-in session as the hosted service gave it: who, and the session
/// itself (as JSON, to keep and resume from).
typedef SignedIn = ({String userId, String email, String session});

/// Why something to do with signing in didn't work.
base class AuthProblem implements Exception {
  const AuthProblem(this.message, {this.offline = false});
  final String message;

  /// It couldn't reach the service: try again later (nothing's wrong with
  /// the account).
  final bool offline;

  @override
  String toString() => message;
}

/// Signing in with the hosted service: what [AccountService] needs, so it
/// can be tested without a network.
abstract interface class AuthBackend {
  /// Emails a sign-in code to [email] (making the account the first time).
  Future<void> sendCode(String email);

  /// Signs in with the emailed [code].
  Future<SignedIn> verifyCode(String email, String code);

  /// Picks up a kept [session], refreshing it if it's expired. Null when
  /// the service no longer accepts it (signed out elsewhere, deleted);
  /// throws an offline [AuthProblem] when it can't be reached.
  Future<SignedIn?> resume(String session);

  /// The session each time it's refreshed (to keep the latest).
  Stream<SignedIn> get refreshed;

  /// Ends the session on the service (best effort: offline is fine).
  Future<void> signOut();

  /// The signed-in person's personal space (made the first time, with
  /// [profileId] as their profile in it): its org id.
  Future<String> ensurePersonalSpace(String name, String profileId);
}

/// [AuthBackend] on the hosted Supabase project.
class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend({SupabaseClient? client})
    : client =
          client ??
          SupabaseClient(
            HostedService.url,
            HostedService.publishableKey,
            authOptions: const AuthClientOptions(
              // A typed code, not a link back into the app: no PKCE
              // verifier to keep.
              authFlowType: AuthFlowType.implicit,
            ),
          );

  final SupabaseClient client;

  GoTrueClient get _auth => client.auth;

  static SignedIn _signedIn(Session s) => (
    userId: s.user.id,
    email: s.user.email ?? '',
    session: jsonEncode(s.toJson()),
  );

  @override
  Stream<SignedIn> get refreshed => _auth.onAuthStateChange
      .where(
        (s) =>
            s.session != null &&
            (s.event == AuthChangeEvent.tokenRefreshed ||
                s.event == AuthChangeEvent.signedIn),
      )
      .map((s) => _signedIn(s.session!));

  @override
  Future<void> sendCode(String email) => _guard(
    () => _auth.signInWithOtp(email: email.trim(), shouldCreateUser: true),
  );

  @override
  Future<SignedIn> verifyCode(String email, String code) => _guard(() async {
    final response = await _auth.verifyOTP(
      type: OtpType.email,
      email: email.trim(),
      token: code.trim(),
    );
    final session = response.session;
    if (session == null) {
      throw const AuthProblem('That code didn’t work. Try a new one.');
    }
    return _signedIn(session);
  });

  @override
  Future<SignedIn?> resume(String session) async {
    try {
      final response = await _auth.recoverSession(session);
      return switch (response.session) {
        final s? => _signedIn(s),
        null => null,
      };
    } on AuthRetryableFetchException {
      throw const AuthProblem('Offline.', offline: true);
    } on AuthException {
      // Refused: the session is over.
      return null;
    } catch (_) {
      throw const AuthProblem('Offline.', offline: true);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Offline: the session simply expires on its own.
    }
  }

  @override
  Future<String> ensurePersonalSpace(String name, String profileId) =>
      _guard(() async {
        final org = await client.rpc(
          'ensure_personal_space',
          params: {'space_name': name, 'new_profile': profileId},
        );
        return org as String;
      });

  /// Turns the service's errors into [AuthProblem]s people can read.
  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AuthProblem {
      rethrow;
    } on AuthRetryableFetchException {
      throw const AuthProblem(
        'Can’t reach the service. Check your connection and try again.',
        offline: true,
      );
    } on AuthException catch (e) {
      throw AuthProblem(_friendly(e));
    } on PostgrestException catch (e) {
      throw AuthProblem(e.message);
    } catch (e) {
      throw AuthProblem(
        'Can’t reach the service. Check your connection and try again.',
        offline: true,
      );
    }
  }

  static String _friendly(AuthException e) {
    final code = e.code ?? '';
    if (code == 'otp_expired' || e.message.toLowerCase().contains('expired')) {
      return 'That code is wrong or has expired. Check it, or send a new one.';
    }
    if (code == 'over_email_send_rate_limit' ||
        code == 'over_request_rate_limit' ||
        e.statusCode == '429') {
      return 'Too many codes sent. Wait a minute, then try again.';
    }
    if (code == 'email_address_invalid' || code == 'validation_failed') {
      return 'That doesn’t look like an email address.';
    }
    return e.message;
  }
}
