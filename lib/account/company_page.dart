import 'dart:async';
import 'dart:io';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../profiles/profile.dart';
import '../profiles/profile_avatar.dart';
import '../files/storage_stats.dart';
import '../profiles/profiles_scope.dart';
import '../projects/project.dart';
import '../projects/project_dashboard.dart'
    show
        AvatarStack,
        BigNumber,
        DashboardCells,
        DashboardTile,
        TotalTile,
        dashboardCountUp;
import '../projects/project_stats.dart';
import '../tasks/task.dart';
import '../settings/settings_repository.dart';
import '../tasks/task_repository.dart';
import '../tasks/form_buttons.dart' show formFieldHeight;
import '../widgets/bottom_fade.dart';
import '../widgets/fade_in_view.dart';
import '../widgets/frosted_bar.dart';
import '../widgets/list_heading.dart';
import '../widgets/selected_text.dart';
import '../widgets/watched.dart';
import 'account_service.dart';
import 'auth_backend.dart' show AuthProblem;

/// The company: on the left, its name and mark, who has joined (their
/// avatars in a row, as on a project's dashboard) and its total tasks; on
/// the right, its people and their roles, with inviting by email at the
/// top, then invites not taken up yet. For its owner and admins; someone
/// not in a company yet starts one here first.
class CompanyPage extends StatefulWidget {
  const CompanyPage({
    super.key,
    required this.accounts,
    this.tasks,
    this.projects = const [],
    this.settings,
  });
  final AccountService accounts;

  /// For the background images in use, in the storage numbers.
  final SettingsRepository? settings;

  /// Every task, for the company's total (none without).
  final TaskRepository? tasks;

  /// The projects this profile sees: the shared ones are the company's.
  final List<Project> projects;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

/// The left panel's width beside the lists.
const _panelWidth = 320.0;

/// Below this width the panel goes above the lists instead of beside them.
const _sideBySide = 760.0;

class _CompanyPageState extends State<CompanyPage>
    with SingleTickerProviderStateMixin {
  /// The panel's opening animation, as on a project's dashboard: once the
  /// page has faded in and the people are loaded, the numbers count up
  /// and the avatars appear one by one.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );
  bool _faded = false;

  /// What the files take up (null until measured): worked out off the
  /// build, from the files on this Mac, when the page opens and again
  /// shortly after tasks change.
  StorageStats? _storage;
  StreamSubscription<List<Task>>? _taskChanges;
  Timer? _remeasure;
  bool _measuring = false;

  Future<void> _measure() async {
    if (_measuring || !mounted) return;
    _measuring = true;
    try {
      final repo = widget.tasks;
      final scope = ProfilesScope.maybeOf(context);
      final wanted = <(StoredKind, File)>[
        if (repo != null)
          for (final t in repo.current()) ...[
            for (final name in t.images)
              (StoredKind.cardImages, repo.imageFile(name)),
            for (final a in t.attachments)
              (StoredKind.attachments, repo.imageFile(a.file)),
          ],
        if (scope != null)
          for (final p in scope.profiles)
            if (scope.imageOf(p) case final file?)
              (StoredKind.profilePhotos, file),
        if (widget.settings case final settings?)
          for (final name in settings.backgroundImagesInUse)
            (StoredKind.backgrounds, settings.backgroundFile(name)),
      ];
      final files = <StoredFile>[];
      for (final (kind, file) in wanted) {
        int? size;
        try {
          size = await file.length();
        } on FileSystemException {
          size = null; // not on this Mac (yet)
        }
        files.add((kind: kind, name: file.path, size: size));
      }
      final stats = storageStats(files);
      if (mounted) setState(() => _storage = stats);
    } finally {
      _measuring = false;
    }
  }

  void _startIntro() {
    if (_faded && _list != null && !_intro.isAnimating && _intro.value == 0) {
      _intro.forward();
    }
  }

  /// [companyStats] for the last tasks and projects seen, worked out again
  /// only when either changes (not on every keystroke in the form).
  (List<Task>, List<Project>, CompanyStats)? _stats;
  CompanyStats _statsFor(List<Task> tasks) {
    final last = _stats;
    if (last != null &&
        identical(last.$1, tasks) &&
        identical(last.$2, widget.projects)) {
      return last.$3;
    }
    final stats = companyStats(widget.projects, tasks);
    _stats = (tasks, widget.projects, stats);
    return stats;
  }

  final _email = AppTextController();
  final _emailFocus = FocusNode();
  final _name = AppTextController();
  String _role = 'member';

  /// An existing person (a profile with no login yet) being invited: they
  /// become that profile, keeping its tasks, when they join.
  Profile? _inviting;

  /// The people and invites, loaded from the service (null while
  /// loading); reloaded after each change.
  ({List<OrgPerson> people, List<OrgInvite> invites})? _list;

  /// Why loading or the last action didn't work, or what it did.
  String? _message;
  bool _messageIsError = false;
  bool _busy = false;

  AccountService get _accounts => widget.accounts;

  @override
  void initState() {
    super.initState();
    _accounts.account.addListener(_accountChanged);
    _load();
    // After the first frame: measuring reads the profiles from context.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    _taskChanges = widget.tasks?.watch().listen((_) {
      _remeasure?.cancel();
      _remeasure = Timer(const Duration(seconds: 1), _measure);
    });
  }

  @override
  void dispose() {
    _accounts.account.removeListener(_accountChanged);
    _intro.dispose();
    _taskChanges?.cancel();
    _remeasure?.cancel();
    _email.dispose();
    _emailFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  String? _company;
  void _accountChanged() {
    final company = _accounts.account.value?.businessOrgId;
    if (company != _company) _load();
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    _company = _accounts.account.value?.businessOrgId;
    if (_company == null) return;
    try {
      final people = await _accounts.people();
      final invites = await _accounts.invites();
      if (mounted) setState(() => _list = (people: people, invites: invites));
      _startIntro();
    } on AuthProblem catch (e) {
      _say(e.message, error: true);
    }
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on AuthProblem catch (e) {
      _say(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() => _run(() async {
    final email = _email.text.trim();
    final as = _inviting;
    await _accounts.invite(email, role: _role, placeholder: as?.id);
    _email.clear();
    if (mounted) setState(() => _inviting = null);
    _say(
      'Invited ${email.toLowerCase()}'
      '${as == null ? '' : ' as ${as.displayName}'}. They join when they '
      'sign in with that email.',
    );
    await _load();
  });

  Future<void> _create() => _run(() => _accounts.createCompany(_name.text));

  Future<void> _cancel(OrgInvite invite) => _run(() async {
    await _accounts.cancelInvite(invite.id);
    await _load();
  });

  @override
  Widget build(BuildContext context) {
    final account = _accounts.account.value;
    final company = account?.businessOrgId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FrostedBar(
          child: Text(
            account?.businessOrgName ?? 'Company',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          // Fades in on opening, like every view (see FadeInView).
          child: FadeInView(
            onFaded: () {
              _faded = true;
              _startIntro();
            },
            child: company == null
                ? _scrolling(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: _formCard([_startCompany(), ?_messageLine()]),
                      ),
                    ),
                  )
                : _columns(account!),
          ),
        ),
      ],
    );
  }

  /// [child] on a page that scrolls as one, centred, at most [_maxWidth].
  Widget _scrolling(Widget child) => BottomFadeScrollView(
    padding: const EdgeInsets.fromLTRB(_side, 0, _side, bottomFadeHeight),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: child,
      ),
    ),
  );

  static const _side = 24.0, _maxWidth = 1100.0;

  /// The panel and the lists. Side by side, each scrolls by itself, and
  /// the People heading and invite form stay put while the people scroll
  /// up under them. When the window is narrow, the panel goes above the
  /// lists and the page scrolls as one.
  Widget _columns(Account account) {
    final (:head, :rest) = _people(
      // At the top of the People list, under its heading.
      form: _form([
        _inviteRow(owner: account.role == 'owner'),
        ?_messageLine(),
      ]),
    );
    // The rows right under the form; a gap before the next list.
    final lists = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in rest.indexed) ...[
          if (i > 0) const SizedBox(height: 16),
          w,
        ],
      ],
    );
    final panel = _panel(account);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth - _side * 2 < _sideBySide) {
          return _scrolling(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [panel, const SizedBox(height: 16), head, lists],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: _side),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  SizedBox(
                    width: _panelWidth,
                    child: BottomFadeScrollView(
                      padding: const EdgeInsets.only(bottom: bottomFadeHeight),
                      child: panel,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        head,
                        Expanded(
                          child: BottomFadeScrollView(
                            padding: const EdgeInsets.only(
                              bottom: bottomFadeHeight,
                            ),
                            child: lists,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The left panel: the company's name and mark, who has joined, and
  /// its total tasks, as tiles like a project dashboard's.
  Widget _panel(Account account) {
    final repo = widget.tasks;
    Widget tiles(CompanyStats stats) => DashboardCells(
      perRow: 1,
      children: [
        _nameTile(account, stats),
        _joinedTile(),
        TotalTile(total: stats.total, done: stats.done, intro: _intro),
        _storageTile(),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one list heading style; the tiles' top border is under it.
        const ListHeading('Company'),
        if (repo == null)
          tiles((total: 0, done: 0, projects: 0))
        else
          Watched<List<Task>>(
            watch: repo.watch,
            current: repo.current,
            builder: (context, tasks) => tiles(_statsFor(tasks)),
          ),
      ],
    );
  }

  /// The company's mark (its initial on the accent, until it has a logo)
  /// and name, with the viewer's role and how many projects it has.
  Widget _nameTile(Account account, CompanyStats stats) {
    final colors = context.colors;
    final scheme = Theme.of(context).colorScheme;
    final name = account.businessOrgName ?? 'Company';
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    return DashboardTile(
      padding: const EdgeInsets.all(20),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: formRadius,
            ),
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
          Expanded(
            child: Column(
              // Centred on the logo, top to bottom.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                Text(
                  '${account.role == null ? '' : '${roleLabel(account.role!)} · '}'
                  '${stats.projects} '
                  'project${stats.projects == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 12, color: colors.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Everyone who has joined: how many, counting up, and their avatars in
  /// a row appearing one by one, as on a project's dashboard. Open invites
  /// are in the Invited list.
  Widget _joinedTile() {
    final list = _list;
    final scope = ProfilesScope.maybeOf(context);
    final people = <Profile>[
      for (final p in list?.people ?? const <OrgPerson>[])
        scope?.find(p.profileId) ?? _emailProfile(p.userId, p.email),
    ];
    final muted = TextStyle(fontSize: 12, color: context.colors.mutedText);
    return DashboardTile(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => BigNumber(
              label: 'People joined',
              value: (people.length * dashboardCountUp.transform(_intro.value))
                  .round(),
            ),
          ),
          const SizedBox(height: 12),
          if (list == null)
            Text('Loading…', style: muted)
          else if (people.isNotEmpty)
            AvatarStack(people: people, intro: _intro),
        ],
      ),
    );
  }

  /// What the files take up: the total, counting up like the other
  /// numbers, then a bar split by kind and a row per kind.
  Widget _storageTile() {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final muted = TextStyle(fontSize: 12, color: colors.mutedText);
    final storage = _storage;
    // Each kind a step lighter of the accent, so the bar follows the
    // theme like everything else.
    Color shade(StoredKind k) => accent.withValues(alpha: 1 - k.index * 0.22);
    return DashboardTile(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => BigNumber(
              label: 'Storage used',
              value:
                  ((storage?.bytes ?? 0) *
                          dashboardCountUp.transform(_intro.value))
                      .round(),
              format: formatBytes,
            ),
          ),
          const SizedBox(height: 12),
          if (storage == null)
            Text('Measuring…', style: muted)
          else ...[
            SizedBox(
              height: 6,
              child: storage.bytes == 0
                  ? ColoredBox(color: colors.divider)
                  : Row(
                      children: [
                        for (final k in storage.kinds)
                          if (k.bytes > 0)
                            Expanded(
                              // Whole-number shares of the bar; a tiny
                              // kind still shows as a sliver.
                              flex: (k.bytes * 1000 / storage.bytes).ceil(),
                              child: ColoredBox(color: shade(k.kind)),
                            ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            for (final k in storage.kinds)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  spacing: 8,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: shade(k.kind),
                        borderRadius: formRadius,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        k.kind.label,
                        style: TextStyle(fontSize: 13, color: colors.text),
                      ),
                    ),
                    Text(
                      '${k.files} file${k.files == 1 ? '' : 's'}',
                      style: muted,
                    ),
                    SizedBox(
                      width: 64,
                      child: Text(
                        formatBytes(k.bytes),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (storage.missing > 0)
              Text(
                '${storage.missing} file${storage.missing == 1 ? '' : 's'} '
                'not on this Mac yet, not counted',
                style: muted,
              ),
          ],
        ],
      ),
    );
  }

  /// Someone known only by their email (no profile here yet): a profile
  /// named by it, so the avatar shows its first letter.
  Profile _emailProfile(String id, String email) =>
      Profile(id: id, name: email, createdAt: DateTime.utc(2026));

  /// The form at the top (invite, or start a company) and what it last
  /// said, on a card: the card shade with its border, square like the
  /// lists below.
  Widget _formCard(List<Widget> children) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.card,
      border: Border.all(color: context.colors.cardBorder),
    ),
    child: _form(children),
  );

  /// A form's fields and its message, padded.
  Widget _form(List<Widget> children) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: children,
    ),
  );

  Widget? _messageLine() => switch (_message) {
    final m? => Text(
      m,
      style: TextStyle(
        fontSize: 12.5,
        color: _messageIsError
            ? Theme.of(context).colorScheme.error
            : context.colors.mutedText,
      ),
    ),
    null => null,
  };

  /// The row's fields, Role box and button share these: [formFieldHeight]
  /// tall, text 13px, [_inset] in from the left, centred top to bottom.
  static const _inset = 12.0;
  static const _fontSize = 13.0;

  /// A one-line field filling a [formFieldHeight] box (expands, so the
  /// outline is the box's full height whatever the Mac's density).
  Widget _textField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String hint,
    TextInputType? keyboardType,
    required VoidCallback onSubmit,
  }) => SizedBox(
    height: formFieldHeight,
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      expands: true,
      maxLines: null,
      textAlignVertical: TextAlignVertical.center,
      style: const TextStyle(fontSize: _fontSize),
      decoration: _field(hint),
      onSubmitted: (_) => onSubmit(),
    ),
  );

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontSize: _fontSize,
      color: context.colors.placeholder,
    ),
    isDense: true,
    // An outline border insets the text 3 more by itself: take that off,
    // so the text starts where the Role box's does.
    contentPadding: const EdgeInsets.fromLTRB(_inset - 3, 0, _inset, 0),
    enabledBorder: context.colors.fieldBorder,
    border: context.colors.fieldBorder,
    focusedBorder: context.colors.fieldBorder,
  );

  ButtonStyle get _buttonStyle => FilledButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    // The theme's button text (in the app's font), at the fields' size.
    textStyle: Theme.of(context).textTheme.labelLarge
        ?.copyWith(fontSize: _fontSize),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    minimumSize: const Size(0, formFieldHeight),
    fixedSize: const Size.fromHeight(formFieldHeight),
    shape: formShape,
  );

  /// Not in a company yet: name one to start it (they become its owner).
  Widget _startCompany() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 10,
    children: [
      Text(
        'Start your company to invite people. Your personal project stays '
        'yours.',
        style: TextStyle(fontSize: 13, color: context.colors.mutedText),
      ),
      Row(
        spacing: 8,
        children: [
          Expanded(
            child: _textField(
              controller: _name,
              hint: 'Company name',
              onSubmit: _create,
            ),
          ),
          FilledButton(
            onPressed: _busy ? null : _create,
            style: _buttonStyle,
            child: const Text('Start company'),
          ),
        ],
      ),
    ],
  );

  /// An email and the role to invite them as (only the owner can invite
  /// admins), then Invite.
  Widget _inviteRow({required bool owner}) => Row(
    spacing: 8,
    children: [
      if (_inviting case final p?) _invitingChip(p),
      Expanded(
        child: _textField(
          controller: _email,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          hint: _inviting == null
              ? 'Invite by email'
              : '${_inviting!.displayName}’s email',
          onSubmit: _invite,
        ),
      ),
      if (owner) _rolePicker(),
      FilledButton(
        onPressed: _busy ? null : _invite,
        style: _buttonStyle,
        child: const Text('Invite'),
      ),
    ],
  );

  /// Who's being invited, before the email: ✕ goes back to inviting
  /// someone new.
  Widget _invitingChip(Profile p) {
    final scope = ProfilesScope.maybeOf(context);
    return Container(
      height: formFieldHeight,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: formRadius,
        border: Border.all(color: context.colors.formBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          ProfileAvatar(profile: p, image: scope?.imageOf(p), size: 22),
          Text(p.displayName, style: const TextStyle(fontSize: 13)),
          IconButton(
            tooltip: 'Invite someone new instead',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _inviting = null),
            icon: const Icon(Symbols.close),
          ),
        ],
      ),
    );
  }

  Widget _rolePicker() => PopupMenuButton<String>(
    tooltip: 'Invite as',
    initialValue: _role,
    position: PopupMenuPosition.under,
    color: context.colors.surface,
    onSelected: (r) => setState(() => _role = r),
    itemBuilder: (_) => [
      for (final r in const ['member', 'admin'])
        PopupMenuItem(
          value: r,
          height: 34,
          child: Row(
            spacing: 10,
            children: [
              SizedBox(
                width: 16,
                child: r == _role
                    ? Icon(Symbols.check, size: 16, color: context.colors.text)
                    : null,
              ),
              Text(roleLabel(r), style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
    ],
    child: Container(
      height: formFieldHeight,
      padding: const EdgeInsets.only(left: _inset, right: 8),
      decoration: BoxDecoration(
        borderRadius: formRadius,
        border: Border.all(color: context.colors.formBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(roleLabel(_role), style: const TextStyle(fontSize: 13)),
          Icon(Symbols.expand_more, size: 16, color: context.colors.text),
        ],
      ),
    ),
  );

  /// The members, with [form] (inviting) at the top of their list, then
  /// invites not taken up yet.
  ({Widget head, List<Widget> rest}) _people({required Widget form}) {
    final list = _list;
    if (list == null) {
      final (:head, :body) = _boxParts(
        'People',
        [
          if (_message == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Loading…',
                style: TextStyle(fontSize: 13, color: context.colors.mutedText),
              ),
            ),
        ],
        top: form,
        count: () => null,
      );
      return (head: head, rest: [?body]);
    }
    final scope = ProfilesScope.maybeOf(context);
    // Everyone in the app without a login yet (and not invited): the
    // company's too, waiting for an invite.
    final taken = {
      for (final p in list.people) p.profileId,
      for (final i in list.invites) ?i.profileId,
    };
    final waiting = [
      for (final p in scope?.profiles ?? const <Profile>[])
        if (!taken.contains(p.id)) p,
    ];
    final (:head, :body) = _boxParts('People', top: form, [
      for (final p in list.people)
        _row(
          leading: switch (scope?.find(p.profileId)) {
            final profile? => ProfileAvatar(
              profile: profile,
              image: scope!.imageOf(profile),
              size: 24,
            ),
            null => _blankAvatar(),
          },
          name: scope?.find(p.profileId)?.displayName,
          email: p.email,
          role: roleLabel(p.role),
        ),
      for (final p in waiting)
        _row(
          leading: ProfileAvatar(
            profile: p,
            image: scope!.imageOf(p),
            size: 24,
          ),
          name: p.displayName,
          email: 'Not signed in yet',
          role: '',
          // In the role's place, centred under the roles above.
          trailing: TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _inviting = p);
                    _emailFocus.requestFocus();
                  },
            // A button, but no taller than the other rows.
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Invite'),
          ),
        ),
    ]);
    return (
      head: head,
      rest: [
        ?body,
        if (list.invites.isNotEmpty)
          _box('Invited', [
            for (final i in list.invites)
              _row(
                leading: switch (scope?.find(i.profileId)) {
                  final profile? => ProfileAvatar(
                    profile: profile,
                    image: scope!.imageOf(profile),
                    size: 24,
                  ),
                  null => _blankAvatar(icon: Symbols.mail),
                },
                name: scope?.find(i.profileId)?.displayName,
                email: i.email,
                role: roleLabel(i.role),
                action: IconButton(
                  tooltip: 'Cancel invite',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : () => _cancel(i),
                  icon: const Icon(Symbols.close),
                ),
              ),
          ]),
      ],
    );
  }

  Widget _blankAvatar({IconData icon = Symbols.person}) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: context.colors.hover,
    ),
    child: Icon(icon, size: 14, color: context.colors.mutedText),
  );

  /// A heading, then its rows boxed together on the card shade (square,
  /// like Activity and the list view).
  /// [top] (a form) goes first in the box, above the rows; [count] is
  /// the rows' unless given (null while loading: none shown).
  Widget _box(
    String heading,
    List<Widget> rows, {
    Widget? top,
    int? Function()? count,
  }) {
    final (:head, :body) = _boxParts(heading, rows, top: top, count: count);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [head, ?body],
    );
  }

  /// A [_box] in two: [head] (the heading, and [top] boxed under it) and
  /// [body] (the rows, boxed on: no top border, [top]'s bottom one is
  /// right over them; null with no rows). Apart, the rows can scroll up
  /// under [head] and go out of sight at its bottom edge.
  ({Widget head, Widget? body}) _boxParts(
    String heading,
    List<Widget> rows, {
    Widget? top,
    int? Function()? count,
  }) {
    final colors = context.colors;
    final line = BorderSide(color: colors.cardBorder);
    Widget boxed(List<Widget> children, Border border) => DecoratedBox(
      decoration: BoxDecoration(color: colors.card, border: border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in children.indexed) ...[
            if (i > 0) Divider(height: 1, color: colors.cardBorder),
            row,
          ],
        ],
      ),
    );
    // The one list heading style (see ListHeading); no line of its own:
    // the box's top border is right under it.
    final heading_ = ListHeading(
      heading,
      count: count == null ? rows.length : count(),
      squareCount: true,
    );
    final head = top == null
        ? heading_
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading_,
              boxed([top], Border.fromBorderSide(line)),
            ],
          );
    final body = rows.isEmpty
        ? null
        : boxed(
            rows,
            top == null
                ? Border.fromBorderSide(line)
                : Border(left: line, right: line, bottom: line),
          );
    return (head: head, body: body);
  }

  Widget _row({
    required Widget leading,
    String? name,
    required String email,
    required String role,
    Widget? trailing,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      spacing: 10,
      children: [
        leading,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name != null && name.isNotEmpty)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: name == null || name.isEmpty ? 13 : 12,
                  color: name == null || name.isEmpty
                      ? context.colors.text
                      : context.colors.mutedText,
                ),
              ),
            ],
          ),
        ),
        // The role (or Invite) centred in one column, close to the right
        // edge; ✕ after it where there is one (invites).
        SizedBox(
          width: 64,
          child: Center(
            child: trailing ?? Text(role, style: const TextStyle(fontSize: 13)),
          ),
        ),
        ?action,
      ],
    ),
  );
}
