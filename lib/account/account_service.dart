import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sync_engine/sync_engine.dart';

import 'auth_backend.dart';

export 'auth_backend.dart' show OrgInvite, OrgPerson;

/// Who's signed in on this Mac.
@immutable
final class Account {
  const Account({
    required this.userId,
    required this.email,
    this.personalOrgId,
    this.role,
    this.businessOrgId,
    this.businessOrgName,
  });

  final String userId;
  final String email;

  /// Their personal space (an org of one), once the service has made it.
  final String? personalOrgId;

  /// Their role in the org they work in (their business org if they're in
  /// one, otherwise their personal space): `owner`, `admin` or `member`.
  /// Null until the service has said; kept for offline.
  final String? role;

  /// Their company (business org), if they're in one, and its name.
  final String? businessOrgId;
  final String? businessOrgName;

  /// They can see the company's people and invite: its owner or an
  /// admin, or anyone not in one yet (to start it: they own their
  /// personal space).
  bool get managesCompany => role == 'owner' || role == 'admin';

  Account copyWith({String? personalOrgId}) => Account(
    userId: userId,
    email: email,
    personalOrgId: personalOrgId ?? this.personalOrgId,
    role: role,
    businessOrgId: businessOrgId,
    businessOrgName: businessOrgName,
  );

  Account withStanding(OrgStanding s) => Account(
    userId: userId,
    email: email,
    personalOrgId: personalOrgId,
    role: s.role,
    businessOrgId: s.businessOrgId,
    businessOrgName: s.businessOrgName,
  );

  Map<String, Object?> toJson() => {
    'userId': userId,
    'email': email,
    'personalOrgId': personalOrgId,
    'role': role,
    'businessOrgId': businessOrgId,
    'businessOrgName': businessOrgName,
  };

  static Account? fromJson(Map<String, Object?>? json) => switch (json) {
    {'userId': final String id, 'email': final String email} => Account(
      userId: id,
      email: email,
      personalOrgId: json['personalOrgId'] as String?,
      role: json['role'] as String?,
      businessOrgId: json['businessOrgId'] as String?,
      businessOrgName: json['businessOrgName'] as String?,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is Account &&
      other.userId == userId &&
      other.email == email &&
      other.personalOrgId == personalOrgId &&
      other.role == role &&
      other.businessOrgId == businessOrgId &&
      other.businessOrgName == businessOrgName;

  @override
  int get hashCode => Object.hash(
    userId,
    email,
    personalOrgId,
    role,
    businessOrgId,
    businessOrgName,
  );
}

/// How a role reads: "Owner", "Admin", "Member" (an unknown one as is).
String roleLabel(String role) => switch (role) {
  'owner' => 'Owner',
  'admin' => 'Admin',
  'member' => 'Member',
  _ => role,
};

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
      if (!devBypassSignIn) {
        _clear();
      } else {
        await _refreshRole();
      }
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
      await _refreshRole();
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
    if (!_isEmail(trimmed)) {
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
    final before = Account.fromJson(_store.get(_ui, _accountKey));
    final same = before?.userId == signedIn.userId;
    _save(
      Account(
        userId: signedIn.userId,
        email: signedIn.email,
        // Same person again: the space (and standing) they had.
        personalOrgId: same ? before?.personalOrgId : null,
        role: same ? before?.role : null,
        businessOrgId: same ? before?.businessOrgId : null,
        businessOrgName: same ? before?.businessOrgName : null,
      ),
      signedIn.session,
    );
    await _ensureSpace();
    await _refreshRole();
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
        current.copyWith(personalOrgId: org),
        _store.get(_ui, _accountKey)?['session'] as String?,
      );
    } on AuthProblem {
      // Offline or refused: the app works without it for now.
    }
  }

  /// Asks the service where they stand (their role can change: made an
  /// admin, joined a company), keeping the last known when offline.
  Future<void> _refreshRole() async {
    final current = account.value;
    if (current == null) return;
    try {
      final standing = await _companies(current).standing();
      final now = account.value;
      if (standing.role == null || now?.userId != current.userId) return;
      final updated = now!.withStanding(standing);
      if (updated != now) _save(updated, _session);
    } on AuthProblem {
      // Offline: the kept standing stays.
    }
  }

  String? get _session => _store.get(_ui, _accountKey)?['session'] as String?;

  static bool _isDev(Account a) => a.userId.startsWith(_devUserPrefix);

  /// TEMPORARY, with [devBypassSignIn]: the made-up account can't reach
  /// the service, so its company is faked on this Mac (see [_DevCompany]).
  late final _devCompany = _DevCompany(
    _store,
    me: () => account.value,
    profileId: profileId,
  );

  /// Where company calls go: the service, or the fake for the made-up
  /// account.
  _CompanyCalls _companies(Account a) =>
      _isDev(a) ? _devCompany : _ServiceCompany(_backend);

  Account _signedIn() => switch (account.value) {
    final a? => a,
    null => throw const AuthProblem('Sign in first.'),
  };

  String _company() => switch (_signedIn().businessOrgId) {
    final org? => org,
    null => throw const AuthProblem('Start a company first.'),
  };

  /// Starts a company (a business org) with them as its owner.
  Future<void> createCompany(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const AuthProblem('Give the company a name.');
    final a = _signedIn();
    final profile = profileId();
    if (profile == null) throw const AuthProblem('Make a profile first.');
    await _companies(a).createBusinessOrg(trimmed, profile);
    await _refreshRole();
  }

  /// The company's members, oldest first.
  Future<List<OrgPerson>> people() =>
      _companies(_signedIn()).people(_company());

  /// Invites not taken up yet, newest first.
  Future<List<OrgInvite>> invites() =>
      _companies(_signedIn()).invites(_company());

  /// Invites [email] to the company as [role] (`admin` or `member`); as
  /// the existing profile [placeholder] (keeping its tasks), if given.
  Future<void> invite(
    String email, {
    String role = 'member',
    String? placeholder,
  }) {
    final address = email.trim().toLowerCase();
    if (!_isEmail(address)) {
      throw const AuthProblem('That doesn’t look like an email address.');
    }
    return _companies(_signedIn())
        .invite(_company(), address, role, placeholder: placeholder);
  }

  Future<void> cancelInvite(String inviteId) =>
      _companies(_signedIn()).cancelInvite(inviteId);

  static bool _isEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

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

/// The company calls [AccountService] makes.
abstract interface class _CompanyCalls {
  Future<OrgStanding> standing();
  Future<String> createBusinessOrg(String name, String profileId);
  Future<List<OrgPerson>> people(String org);
  Future<List<OrgInvite>> invites(String org);
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  });
  Future<void> cancelInvite(String inviteId);
}

/// The real thing: the hosted service.
class _ServiceCompany implements _CompanyCalls {
  _ServiceCompany(this._b);
  final AuthBackend _b;

  @override
  Future<OrgStanding> standing() => _b.standing();
  @override
  Future<String> createBusinessOrg(String name, String profileId) =>
      _b.createBusinessOrg(name, profileId);
  @override
  Future<List<OrgPerson>> people(String org) => _b.people(org);
  @override
  Future<List<OrgInvite>> invites(String org) => _b.invites(org);
  @override
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  }) => _b.invite(org, email, role, placeholder: placeholder);
  @override
  Future<void> cancelInvite(String inviteId) => _b.cancelInvite(inviteId);
}

/// TEMPORARY, with [devBypassSignIn]: a pretend company for the made-up
/// 123456 account, kept on this Mac only (`ui/devCompany`, not synced),
/// so the Company view can be used before sign-in emails work. It's
/// "codename", with the made-up account as its owner; invites are only
/// listed, never sent. Delete with the bypass.
class _DevCompany implements _CompanyCalls {
  _DevCompany(this._store, {required this.me, required this.profileId});
  final LocalStore _store;
  final Account? Function() me;
  final String? Function() profileId;

  static const _key = 'devCompany', id = 'dev-codename';

  Map<String, Object?> get _data =>
      _store.get('ui', _key) ?? {'name': 'codename', 'invites': <Object?>[]};

  List<Map<String, Object?>> get _invites => [
    for (final i in (_data['invites'] as List? ?? const []))
      Map<String, Object?>.from(i as Map),
  ];

  void _put(List<Map<String, Object?>> invites) =>
      _store.put('ui', _key, {..._data, 'invites': invites});

  @override
  Future<OrgStanding> standing() async => (
    role: 'owner',
    businessOrgId: id,
    businessOrgName: _data['name'] as String? ?? 'codename',
  );

  @override
  Future<String> createBusinessOrg(String name, String profileId) async {
    _store.put('ui', _key, {..._data, 'name': name});
    return id;
  }

  @override
  Future<List<OrgPerson>> people(String org) async => [
    if (me() case final a?)
      (
        userId: a.userId,
        email: a.email,
        role: 'owner',
        profileId: profileId() ?? '',
      ),
  ];

  @override
  Future<List<OrgInvite>> invites(String org) async => [
    for (final i in _invites)
      (
        id: i['id'] as String,
        email: i['email'] as String,
        role: i['role'] as String,
        profileId: i['profileId'] as String?,
      ),
  ];

  @override
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  }) async {
    final invites = _invites;
    if (invites.any((i) => i['email'] == email) || me()?.email == email) {
      throw AuthProblem('$email is already invited or a member.');
    }
    _put([
      {
        'id': 'dev-${DateTime.now().microsecondsSinceEpoch}',
        'email': email,
        'role': role,
        'profileId': placeholder,
      },
      ...invites,
    ]);
  }

  @override
  Future<void> cancelInvite(String inviteId) async =>
      _put([..._invites.where((i) => i['id'] != inviteId)]);
}
