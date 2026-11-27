import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sync_engine/sync_engine.dart';

import 'auth_backend.dart';

/// Who's signed in on this Mac.
@immutable
final class Account {
  const Account({
    required this.userId,
    required this.email,
    this.personalOrgId,
  });

  final String userId;
  final String email;

  /// Their personal space (an org of one), once the service has made it.
  final String? personalOrgId;

  Map<String, Object?> toJson() => {
    'userId': userId,
    'email': email,
    'personalOrgId': personalOrgId,
  };

  static Account? fromJson(Map<String, Object?>? json) => switch (json) {
    {'userId': final String id, 'email': final String email} => Account(
      userId: id,
      email: email,
      personalOrgId: json['personalOrgId'] as String?,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.userId == userId &&
      other.email == email &&
      other.personalOrgId == personalOrgId;

  @override
  int get hashCode => Object.hash(userId, email, personalOrgId);
}

/// The data on this Mac belongs to another account: signing in as this
/// one would mix the two.
final class OtherAccountsMac extends AuthProblem {
  const OtherAccountsMac(this.ownerEmail)
    : super(
        'This Mac has $ownerEmail’s projects and tasks. Sign in as '
        '$ownerEmail.',
      );
  final String ownerEmail;
}

/// TEMPORARY, until sign-in emails work (SMTP): the code 123456 signs in
/// without the service, as a made-up account that stays signed in on this
/// Mac. Set to false (and delete what it guards) to turn it off.
const devBypassSignIn = true;
const devBypassCode = '123456';
const _devSession = 'dev-bypass';
const _devUserPrefix = 'dev:';

/// Signing in and staying signed in, offline-first.
///
/// An account is always needed: signed out, the app shows only the sign-in
/// screen. Once signed in, the app works without a connection: the
/// account and its session are kept on this Mac (the local store's `ui`
/// collection, not synced), so the next launch opens straight away, and
/// the session is refreshed whenever the service can be reached. Only the
/// service saying the session is over (signed out elsewhere, account
/// deleted) signs this Mac out.
///
/// The data on this Mac belongs to the first account that signs in on it
/// ([owner]); another account can't sign in until data is kept per
/// account.
class AccountService {
  AccountService(
    this._store,
    this._backend, {
    required this.profileId,
    required this.profileName,
  });

  final LocalStore _store;
  final AuthBackend _backend;

  /// The profile that's this person's on this Mac (made at first launch):
  /// it becomes their profile in their personal space.
  final String? Function() profileId;
  final String Function() profileName;

  static const _ui = 'ui', _accountKey = 'account', _ownerKey = 'macOwner';

  /// Who's signed in; null shows the sign-in screen.
  late final account = ValueNotifier<Account?>(
    Account.fromJson(_store.get(_ui, _accountKey)),
  );

  /// The account this Mac's data belongs to (whoever signed in first).
  ({String userId, String email})? get owner =>
      switch (_store.get(_ui, _ownerKey)) {
        {'userId': final String id, 'email': final String email} => (
          userId: id,
          email: email,
        ),
        _ => null,
      };

  StreamSubscription<SignedIn>? _refreshes;
  Timer? _retry;

  /// Picks up the kept session (in the background: the app is usable
  /// straight away, offline too), and keeps refreshed sessions.
  void start() {
    _refreshes = _backend.refreshed.listen((s) {
      if (account.value?.userId == s.userId) _keepSession(s.session);
    });
    unawaited(_resume());
  }

  Future<void> _resume() async {
    final kept = _store.get(_ui, _accountKey)?['session'];
    if (account.value == null || kept is! String) return;
    // The made-up account: nothing to resume with the service.
    if (kept == _devSession) {
      if (!devBypassSignIn) _clear();
      return;
    }
    try {
      final resumed = await _backend.resume(kept);
      if (resumed == null) {
        _clear();
        return;
      }
      _keepSession(resumed.session);
      await _ensureSpace();
    } on AuthProblem catch (e) {
      // Offline: stay signed in, try again in a while.
      if (!e.offline) return;
      _retry?.cancel();
      _retry = Timer(const Duration(minutes: 1), () => unawaited(_resume()));
    }
  }

  /// Emails a sign-in code.
  Future<void> sendCode(String email) {
    final trimmed = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed)) {
      throw const AuthProblem('That doesn’t look like an email address.');
    }
    return _backend.sendCode(trimmed);
  }

  /// Signs in with the emailed code, and makes sure there's a personal
  /// space. Throws [AuthProblem] (and [OtherAccountsMac]) when it can't.
  Future<Account> verifyCode(String email, String code) async {
    final address = email.trim().toLowerCase();
    final SignedIn signedIn = devBypassSignIn && code == devBypassCode
        ? (
            userId: '$_devUserPrefix$address',
            email: address,
            session: _devSession,
          )
        : await _backend.verifyCode(address, code);
    var owner = this.owner;
    // A made-up account doesn't own this Mac's data.
    if (owner?.userId.startsWith(_devUserPrefix) ?? false) owner = null;
    if (owner != null && owner.userId != signedIn.userId) {
      await _backend.signOut();
      throw OtherAccountsMac(owner.email);
    }
    if (!signedIn.userId.startsWith(_devUserPrefix) || owner == null) {
      _store.put(_ui, _ownerKey, {
        'userId': signedIn.userId,
        'email': signedIn.email,
      });
    }
    _save(
      Account(
        userId: signedIn.userId,
        email: signedIn.email,
        // Same person again: the space they had.
        personalOrgId: Account.fromJson(_store.get(_ui, _accountKey))
            ?.personalOrgId,
      ),
      signedIn.session,
    );
    await _ensureSpace();
    return account.value!;
  }

  /// Makes the personal space the first time (needs the service; tried
  /// again on the next launch if it couldn't).
  Future<void> _ensureSpace() async {
    final current = account.value;
    final profile = profileId();
    if (current == null || current.personalOrgId != null || profile == null) {
      return;
    }
    // The made-up account has no personal space on the service.
    if (current.userId.startsWith(_devUserPrefix)) return;
    try {
      final org = await _backend.ensurePersonalSpace(profileName(), profile);
      if (account.value?.userId != current.userId) return;
      _save(
        Account(
          userId: current.userId,
          email: current.email,
          personalOrgId: org,
        ),
        _store.get(_ui, _accountKey)?['session'] as String?,
      );
    } on AuthProblem {
      // Offline or refused: the app works without it for now.
    }
  }

  /// Signs out of this Mac. Its data stays (it's still [owner]'s).
  Future<void> signOut() async {
    _clear();
    await _backend.signOut();
  }

  void _save(Account value, String? session) {
    _store.put(_ui, _accountKey, {...value.toJson(), 'session': ?session});
    account.value = value;
  }

  void _keepSession(String session) {
    final kept = _store.get(_ui, _accountKey);
    if (kept == null) return;
    _store.put(_ui, _accountKey, {...kept, 'session': session});
  }

  void _clear() {
    _retry?.cancel();
    _store.delete(_ui, _accountKey);
    account.value = null;
  }

  void dispose() {
    _retry?.cancel();
    _refreshes?.cancel();
    account.dispose();
  }
}
