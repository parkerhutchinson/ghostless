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

  /// Where they stand: their role in the org they work in (their
  /// business org's if they're in one, otherwise their personal space's)
  /// and their business org, if any.
  Future<OrgStanding> standing();

  /// Makes a business org with them as its owner ([profileId] their
  /// profile in it): its id.
  Future<String> createBusinessOrg(String name, String profileId);

  /// [org]'s members, oldest first.
  Future<List<OrgPerson>> people(String org);

  /// [org]'s invites not taken up yet, newest first.
  Future<List<OrgInvite>> invites(String org);

  /// Invites [email] to [org] as [role] (`admin` or `member`). With a
  /// [placeholder], they become that existing profile (keeping its tasks)
  /// when they join.
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  });

  Future<void> cancelInvite(String inviteId);
}

/// Someone's role in the org they work in, and their business org.
typedef OrgStanding = ({
  String? role,
  String? businessOrgId,
  String? businessOrgName,
});

/// From someone's memberships (`org_id`, `kind`, `role`, `orgs.name`
/// each), where they stand: the business org's role, otherwise the
/// personal space's.
OrgStanding standingFrom(List<Map<String, Object?>> memberships) {
  Map<String, Object?>? of(String kind) =>
      memberships.where((m) => m['kind'] == kind).firstOrNull;
  final business = of('business');
  final m = business ?? of('personal');
  return (
    role: m?['role'] as String?,
    businessOrgId: business?['org_id'] as String?,
    businessOrgName: switch (business?['orgs']) {
      {'name': final String name} => name,
      _ => null,
    },
  );
}

/// A member of an org.
typedef OrgPerson = ({
  String userId,
  String email,
  String role,
  String profileId,
});

/// Someone invited to an org who hasn't joined yet.
typedef OrgInvite = ({String id, String email, String role, String? profileId});

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

  @override
  Future<OrgStanding> standing() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) {
      return (role: null, businessOrgId: null, businessOrgName: null);
    }
    // Members can see their orgs' other members too: just their own rows.
    final rows = await client
        .from('org_members')
        .select('org_id, kind, role, orgs(name)')
        .eq('user_id', user.id);
    return standingFrom(rows);
  });

  @override
  Future<String> createBusinessOrg(String name, String profileId) =>
      _guard(() async {
        final org = await client.rpc(
          'create_business_org',
          params: {'org_name': name, 'new_profile': profileId},
        );
        return org as String;
      });

  @override
  Future<List<OrgPerson>> people(String org) => _guard(() async {
    final rows = await client.rpc('org_people', params: {'org': org}) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (
          userId: r['user_id'] as String,
          email: r['email'] as String? ?? '',
          role: r['role'] as String,
          profileId: r['profile_id'] as String,
        ),
    ];
  });

  @override
  Future<List<OrgInvite>> invites(String org) => _guard(() async {
    final rows = await client
        .from('org_invites')
        .select('id, email, role, profile_id')
        .eq('org_id', org)
        .isFilter('accepted_at', null)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          email: r['email'] as String,
          role: r['role'] as String,
          profileId: r['profile_id'] as String?,
        ),
    ];
  });

  @override
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  }) => _guard(
    () => client.rpc(
      'invite_member',
      params: {
        'org': org,
        'invitee_email': email,
        'member_role': role,
        'placeholder': placeholder,
      },
    ),
  );

  @override
  Future<void> cancelInvite(String inviteId) =>
      _guard(() => client.rpc('cancel_invite', params: {'invite': inviteId}));

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
