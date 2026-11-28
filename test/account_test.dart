import 'dart:async';

import 'package:codename/account/account_service.dart';
import 'package:codename/account/auth_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_engine/sync_engine.dart';

/// The hosted service, faked.
class FakeAuth implements AuthBackend {
  final sent = <String>[];
  final spaces = <String, String>{};
  String userFor(String email) => 'user-${email.split('@').first}';

  /// What [resume] does: give a session back, refuse (null), or be
  /// offline (throw).
  SignedIn? Function(String session) onResume = (s) =>
      (userId: 'user-sam', email: 'sam@example.com', session: '$s+refreshed');
  bool offline = false;
  int signOuts = 0;
  final _refreshed = StreamController<SignedIn>.broadcast();

  void refresh(SignedIn s) => _refreshed.add(s);

  @override
  Stream<SignedIn> get refreshed => _refreshed.stream;

  @override
  Future<void> sendCode(String email) async {
    if (offline) throw const AuthProblem('offline', offline: true);
    sent.add(email);
  }

  @override
  Future<SignedIn> verifyCode(String email, String code) async {
    if (code != '246810') throw const AuthProblem('That code didn’t work.');
    return (userId: userFor(email), email: email, session: 'session-$email');
  }

  @override
  Future<SignedIn?> resume(String session) async {
    if (offline) throw const AuthProblem('offline', offline: true);
    return onResume(session);
  }

  @override
  Future<void> signOut() async => signOuts++;

  @override
  Future<String> ensurePersonalSpace(String name, String profileId) async {
    if (offline) throw const AuthProblem('offline', offline: true);
    return spaces.putIfAbsent(profileId, () => 'space-of-$profileId');
  }

  String? role = 'owner';
  String? company;
  final invited = <OrgInvite>[];

  @override
  Future<OrgStanding> standing() async {
    if (offline) throw const AuthProblem('offline', offline: true);
    return (
      role: role,
      businessOrgId: company,
      businessOrgName: company == null ? null : 'Acme',
    );
  }

  @override
  Future<String> createBusinessOrg(String name, String profileId) async {
    if (company != null) throw const AuthProblem('Already in one.');
    role = 'owner';
    return company = 'org-acme';
  }

  @override
  Future<List<OrgPerson>> people(String org) async => [
    (userId: 'user-sam', email: 'sam@example.com', role: role!, profileId: 'p'),
  ];

  @override
  Future<List<OrgInvite>> invites(String org) async => [...invited];

  @override
  Future<void> invite(
    String org,
    String email,
    String role, {
    String? placeholder,
  }) async => invited.insert(0, (
    id: 'i${invited.length}',
    email: email,
    role: role,
    profileId: placeholder,
  ));

  @override
  Future<void> cancelInvite(String inviteId) async =>
      invited.removeWhere((i) => i.id == inviteId);
}

void main() {
  late LocalStore store;
  late FakeAuth auth;

  AccountService service() => AccountService(
    store,
    auth,
    profileId: () => 'profile-1',
    profileName: () => 'Sam Lee',
  );

  setUp(() {
    store = LocalStore.inMemory();
    auth = FakeAuth();
  });

  tearDown(() => store.close());

  test(
    'signed out at first; a code signs in and makes the personal space',
    () async {
      final accounts = service()..start();
      expect(accounts.account.value, isNull);
      await accounts.sendCode('  Sam@Example.com ');
      expect(auth.sent, ['sam@example.com']);
      final account = await accounts.verifyCode('sam@example.com', '246810');
      expect(account.userId, 'user-sam');
      expect(account.personalOrgId, 'space-of-profile-1');
      expect(accounts.account.value, account);
      expect(accounts.owner?.email, 'sam@example.com');
    },
  );

  test('the role: fetched at sign-in, refreshed, kept offline', () async {
    auth.role = 'member';
    await service().verifyCode('sam@example.com', '246810');
    expect(service().account.value?.role, 'member');
    // Made an admin: picked up on the next launch.
    auth.role = 'admin';
    final next = service()..start();
    await pumpEventQueue();
    expect(next.account.value?.role, 'admin');
    // Offline: the last one known stays.
    auth.offline = true;
    final offline = service()..start();
    await pumpEventQueue();
    expect(offline.account.value?.role, 'admin');
  });

  test('standingFrom: the business org’s role, else the personal space’s', () {
    expect(standingFrom([]).role, isNull);
    expect(
      standingFrom([
        {'org_id': 'me', 'kind': 'personal', 'role': 'owner'},
      ]),
      (role: 'owner', businessOrgId: null, businessOrgName: null),
    );
    expect(
      standingFrom([
        {'org_id': 'me', 'kind': 'personal', 'role': 'owner'},
        {
          'org_id': 'acme',
          'kind': 'business',
          'role': 'member',
          'orgs': {'name': 'Acme'},
        },
      ]),
      (role: 'member', businessOrgId: 'acme', businessOrgName: 'Acme'),
    );
    expect(roleLabel('admin'), 'Admin');
  });

  test('a company: started, then people invited and cancelled', () async {
    final accounts = service();
    await accounts.verifyCode('sam@example.com', '246810');
    expect(accounts.account.value!.managesCompany, isTrue);
    expect(
      () => accounts.invite('a@b.co'),
      throwsA(isA<AuthProblem>()),
      reason: 'no company yet',
    );
    await expectLater(
      accounts.createCompany('  '),
      throwsA(isA<AuthProblem>()),
    );
    await accounts.createCompany('Acme');
    expect(accounts.account.value!.businessOrgId, 'org-acme');
    expect(accounts.account.value!.businessOrgName, 'Acme');
    expect(() => accounts.invite('nope'), throwsA(isA<AuthProblem>()));
    await accounts.invite(
      ' New@Example.com ',
      role: 'admin',
      placeholder: 'profile-jo',
    );
    final invites = await accounts.invites();
    expect(invites.single.email, 'new@example.com');
    expect(invites.single.profileId, 'profile-jo');
    expect(invites.single.role, 'admin');
    await accounts.cancelInvite(invites.single.id);
    expect(await accounts.invites(), isEmpty);
    expect((await accounts.people()).single.email, 'sam@example.com');
  });

  test('a member of a company doesn’t manage it', () async {
    auth.role = 'member';
    auth.company = 'org-acme';
    final accounts = service();
    await accounts.verifyCode('sam@example.com', '246810');
    expect(accounts.account.value!.managesCompany, isFalse);
  });

  test(
    'the made-up 123456 account gets a pretend company, kept here',
    () async {
      final accounts = service();
      await accounts.verifyCode('sam@example.com', devBypassCode);
      final account = accounts.account.value!;
      expect(account.role, 'owner');
      expect(account.businessOrgName, 'codename');
      expect((await accounts.people()).single.role, 'owner');
      await accounts.invite('jo@example.com', placeholder: 'profile-jo');
      await expectLater(
        accounts.invite('jo@example.com'),
        throwsA(isA<AuthProblem>()),
      );
      // Across launches.
      final next = service();
      final invites = await next.invites();
      expect(invites.single.profileId, 'profile-jo');
      await next.cancelInvite(invites.single.id);
      expect(await next.invites(), isEmpty);
      expect(auth.invited, isEmpty, reason: 'never reaches the service');
    },
  );

  test('a bad email or code says why', () async {
    final accounts = service();
    expect(() => accounts.sendCode('nope'), throwsA(isA<AuthProblem>()));
    await expectLater(
      accounts.verifyCode('sam@example.com', '000000'),
      throwsA(isA<AuthProblem>()),
    );
    expect(accounts.account.value, isNull);
  });

  test('stays signed in across launches, offline too', () async {
    await service().verifyCode('sam@example.com', '246810');
    auth.offline = true;
    final next = service()..start();
    // Straight away, before (and without) reaching the service.
    expect(next.account.value?.email, 'sam@example.com');
    await pumpEventQueue();
    expect(next.account.value, isNotNull, reason: 'offline keeps you in');
    next.dispose();
  });

  test('a refused session signs this Mac out', () async {
    await service().verifyCode('sam@example.com', '246810');
    auth.onResume = (_) => null;
    final next = service()..start();
    await pumpEventQueue();
    expect(next.account.value, isNull);
    // The data still belongs to them: their email is suggested.
    expect(next.owner?.email, 'sam@example.com');
  });

  test('refreshed sessions are kept for the next launch', () async {
    final accounts = service()..start();
    await accounts.verifyCode('sam@example.com', '246810');
    auth.refresh((
      userId: 'user-sam',
      email: 'sam@example.com',
      session: 'newer',
    ));
    await pumpEventQueue();
    String? resumedWith;
    auth.onResume = (s) {
      resumedWith = s;
      return (userId: 'user-sam', email: 'sam@example.com', session: s);
    };
    service().start();
    await pumpEventQueue();
    expect(resumedWith, 'newer');
  });

  test("the personal space is made later if it couldn't be at first", () async {
    final accounts = service();
    await accounts.verifyCode('sam@example.com', '246810');
    // Signed in, then went offline before it was made (simulated).
    store.put('ui', 'account', {
      ...store.get('ui', 'account')!,
      'personalOrgId': null,
    });
    final next = service()..start();
    expect(next.account.value?.personalOrgId, isNull);
    await pumpEventQueue();
    expect(next.account.value?.personalOrgId, 'space-of-profile-1');
  });

  test(
    "another account can't sign in on this Mac (its data isn't theirs)",
    () async {
      final accounts = service();
      await accounts.verifyCode('sam@example.com', '246810');
      await accounts.signOut();
      expect(accounts.account.value, isNull);
      await expectLater(
        accounts.verifyCode('alex@example.com', '246810'),
        throwsA(
          isA<OtherAccountsMac>().having(
            (e) => e.ownerEmail,
            'owner',
            'sam@example.com',
          ),
        ),
      );
      expect(accounts.account.value, isNull);
      // Signed out on the service too.
      expect(auth.signOuts, 2);
      // The owner can.
      await accounts.verifyCode('sam@example.com', '246810');
      expect(accounts.account.value?.email, 'sam@example.com');
    },
  );

  test('signing out keeps the data and forgets the session', () async {
    final accounts = service();
    await accounts.verifyCode('sam@example.com', '246810');
    await accounts.signOut();
    expect(store.get('ui', 'account'), isNull);
    expect(auth.signOuts, 1);
    expect(service().account.value, isNull);
  });

  test('TEMPORARY: 123456 signs in without the service, and stays', () async {
    auth.offline = true; // Never asked.
    final accounts = service();
    final account = await accounts.verifyCode('me@example.com', devBypassCode);
    expect(account.email, 'me@example.com');
    expect(account.personalOrgId, isNull);
    // Next launch: still signed in (online or not), service never asked.
    auth.offline = false;
    auth.onResume = (_) => fail('resumed a made-up session');
    final next = service()..start();
    await pumpEventQueue();
    expect(next.account.value?.email, 'me@example.com');
    // A real account can still sign in on this Mac afterwards.
    await next.signOut();
    final real = await next.verifyCode('sam@example.com', '246810');
    expect(real.userId, isNot(startsWith('dev:')));
  }, skip: devBypassSignIn ? null : 'bypass is off');
}
