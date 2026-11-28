import 'dart:async';

import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../files/storage_stats.dart' show formatBytes;
import '../projects/project_dashboard.dart'
    show BigNumber, DashboardCells, DashboardTile, dashboardCountUp;
import '../sync/remote_config.dart';
import '../sync/sync_service.dart';
import '../tasks/task_board.dart' show headerButtonFill;
import '../widgets/bottom_fade.dart';
import '../widgets/fade_in_view.dart';
import '../widgets/frosted_bar.dart';
import '../widgets/list_heading.dart';
import 'database_stats.dart';
import 'service_stats.dart';

/// For developers only (the sidebar shows it in debug builds): how big
/// the synced database is, its accounts and orgs, what's changed lately,
/// connections in use, its tables, and the files in storage across every
/// account (and the ones nothing refers to). Asked of the database this Mac syncs with, through a
/// connection of its own, read only.
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key, this.sync, this.measure});

  /// Takes the measurements in place of asking [sync]'s database (tests).
  @visibleForTesting
  final Future<(DatabaseStats, ServiceStats)> Function()? measure;

  /// Where the database is; without a Postgres connection there's
  /// nothing to ask.
  final SyncService? sync;

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage>
    with SingleTickerProviderStateMixin {
  /// The numbers count up once the page has faded in and they've come
  /// back, as on a project's dashboard.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );
  bool _faded = false;

  DatabaseStats? _stats;
  ServiceStats? _service;
  String? _error;
  bool _loading = false;

  PostgresConfig? get _config => switch (widget.sync?.current?.config) {
    final PostgresConfig c => c,
    _ => null,
  };

  /// Measures again when the connection changes (it may still be
  /// connecting when the page opens).
  StreamSubscription<SyncConnection?>? _connection;

  @override
  void initState() {
    super.initState();
    if (widget.measure != null) _load();
    _connection = widget.sync?.watch().listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_stats == null) _load();
    });
  }

  @override
  void dispose() {
    _connection?.cancel();
    _intro.dispose();
    super.dispose();
  }

  void _startIntro() {
    if (_faded && _stats != null && _intro.value == 0) _intro.forward();
  }

  Future<void> _load() async {
    final config = _config;
    if ((config == null && widget.measure == null) || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (stats, service) = await (widget.measure ?? () => _ask(config!))();
      if (mounted) {
        setState(() {
          _stats = stats;
          _service = service;
        });
      }
      _startIntro();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Everything, over one short connection of its own.
  static Future<(DatabaseStats, ServiceStats)> _ask(
    PostgresConfig config,
  ) async {
    final connection = await config.open();
    try {
      return (
        await fetchDatabaseStats(connection),
        await fetchServiceStats(connection),
      );
    } finally {
      await connection.close();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const FrostedBar(
        child: Text(
          'Developer',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
      ),
      Expanded(
        // Fades in on opening, like every view (see FadeInView).
        child: FadeInView(
          onFaded: () {
            _faded = true;
            _startIntro();
          },
          child: BottomFadeScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, bottomFadeHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _content(),
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  List<Widget> _content() {
    final colors = context.colors;
    final muted = TextStyle(fontSize: 13, color: colors.mutedText);
    final config = _config;
    final stats = _stats;
    final heading = ListHeading(
      'Database',
      actions: [
        if (config != null)
          IconButton(
            tooltip: 'Measure again',
            iconSize: 17,
            padding: EdgeInsets.zero,
            style: headerButtonFill(context).merge(
              IconButton.styleFrom(
                fixedSize: const Size(26, 26),
                minimumSize: const Size(26, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            onPressed: _loading ? null : _load,
            icon: const Icon(Symbols.refresh),
          ),
      ],
    );
    Widget note(String text, {bool error = false}) => DashboardCells(
      perRow: 1,
      children: [
        DashboardTile(
          child: Text(
            text,
            style: error
                ? muted.copyWith(color: Theme.of(context).colorScheme.error)
                : muted,
          ),
        ),
      ],
    );
    if (config == null && widget.measure == null) {
      return [
        heading,
        note(
          'Not connected to a Postgres database. Connect one in Settings › '
          'Data to see its size.',
        ),
      ];
    }
    if (stats == null) {
      return [
        heading,
        note(
          _error ?? 'Measuring ${config?.description ?? 'the database'}…',
          error: _error != null,
        ),
      ];
    }
    return [
      heading,
      LayoutBuilder(
        builder: (context, constraints) => DashboardCells(
          perRow: constraints.maxWidth < 620 ? 1 : 2,
          children: [
            _bigTile(
              label: 'Database size',
              bytes: stats.databaseBytes,
              note:
                  '${_n(stats.rows)} rows in ${stats.tables.length} tables '
                  '(${formatBytes(stats.tableBytes)})${config == null ? '' : ' · ${config.description}'}',
            ),
            _bigTile(
              label: 'Storage, all accounts',
              bytes: stats.storageBytes,
              note:
                  '${_n(stats.files)} files in ${stats.buckets.length} '
                  'bucket${stats.buckets.length == 1 ? '' : 's'}',
            ),
          ],
        ),
      ),
      if (_error case final e?) ...[
        const SizedBox(height: 8),
        Text(
          e,
          style: muted.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (_service case final service?) ..._serviceSections(service),
      const SizedBox(height: 16),
      ListHeading('Tables', count: stats.tables.length, squareCount: true),
      _list([
        _row('Table', const ['Rows', 'Size'], header: true),
        for (final t in stats.tables)
          _row(t.name, [_n(t.rows), formatBytes(t.bytes)]),
      ]),
      const SizedBox(height: 16),
      ListHeading(
        'Storage buckets',
        count: stats.buckets.length,
        squareCount: true,
      ),
      _list([
        _row('Bucket', const ['Files', 'Size'], header: true),
        if (stats.buckets.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No files in storage.', style: muted),
          ),
        for (final b in stats.buckets)
          _row(b.name, [_n(b.files), formatBytes(b.bytes)]),
      ]),
    ];
  }

  /// Accounts and orgs, activity, connections and orphaned files.
  List<Widget> _serviceSections(ServiceStats s) {
    final colors = context.colors;
    final muted = TextStyle(fontSize: 13, color: colors.mutedText);
    String plural(int n, String one, [String? many]) =>
        '${_n(n)} ${n == 1 ? one : many ?? '${one}s'}';
    final connections = s.connections;
    final usable = connections.max - connections.reserved;
    final orphans = s.orphans;
    final orphanBytes = orphans?.fold(0, (n, o) => n + o.bytes) ?? 0;
    return [
      // Who's using it.
      const SizedBox(height: 16),
      const ListHeading('Accounts and orgs'),
      LayoutBuilder(
        builder: (context, constraints) => DashboardCells(
          perRow: constraints.maxWidth < 620 ? 1 : 2,
          children: [
            _countTile(
              label: 'Accounts',
              value: s.accounts?.total ?? 0,
              note: switch (s.accounts) {
                final a? =>
                  '${_n(a.newThisWeek)} new this week · '
                      '${_n(a.active7)} signed in this week · '
                      '${_n(a.active30)} this month',
                null => 'No Supabase Auth in this database',
              },
            ),
            _countTile(
              label: 'Business orgs',
              value: s.orgs?.businesses.length ?? 0,
              note: switch (s.orgs) {
                final o? => plural(o.personal, 'personal space'),
                null => 'No orgs tables in this database',
              },
            ),
          ],
        ),
      ),
      if (s.orgs case final orgs? when orgs.businesses.isNotEmpty)
        _list(top: false, [
          _row('Business', const ['Members', 'Open invites'], header: true),
          for (final b in orgs.businesses)
            _row(b.name, [_n(b.members), _n(b.openInvites)]),
        ]),

      // What's changed lately, per synced table.
      const SizedBox(height: 16),
      ListHeading('Activity', count: s.activity.length, squareCount: true),
      _list([
        _row('Table', const [
          'Rows',
          'Last 24h',
          'Last 7d',
          'Deleted, kept',
        ], header: true),
        for (final a in s.activity)
          _row(a.name, [
            _n(a.live),
            _n(a.changed24h),
            _n(a.changed7d),
            _n(a.deleted),
          ]),
      ]),

      // Connections: the first limit to hit as more Macs sync.
      const SizedBox(height: 16),
      const ListHeading('Connections'),
      DashboardCells(
        perRow: 1,
        children: [
          DashboardTile(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedBuilder(
                  animation: _intro,
                  builder: (context, _) => BigNumber(
                    label: 'In use',
                    value:
                        (connections.inUse *
                                dashboardCountUp.transform(_intro.value))
                            .round(),
                    format: (v) => '$v / ${connections.max}',
                  ),
                ),
                const SizedBox(height: 12),
                // Used out of all, on a track: how close to the limit.
                SizedBox(
                  height: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: colors.divider),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: connections.max == 0
                            ? 0
                            : (connections.inUse / connections.max).clamp(0, 1),
                        child: ColoredBox(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_n(connections.reserved)} kept for administrators · '
                  '${_n((usable - connections.inUse).clamp(0, usable))} '
                  'free for apps',
                  style: TextStyle(fontSize: 12, color: colors.mutedText),
                ),
              ],
            ),
          ),
        ],
      ),
      _list(top: false, [
        _row('Held by (database user)', const ['Connections'], header: true),
        for (final u in connections.byUser) _row(u.user, [_n(u.count)]),
      ]),

      // Files nothing refers to: storage paid for, for nothing.
      if (orphans != null) ...[
        const SizedBox(height: 16),
        ListHeading('Orphaned files', count: orphans.length, squareCount: true),
        _list([
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              orphans.isEmpty
                  ? 'Every file in storage belongs to a task, profile or '
                        'background.'
                  : '${plural(orphans.length, 'file')} '
                        '(${formatBytes(orphanBytes)}) in storage that no '
                        'task, profile or background refers to.',
              style: muted,
            ),
          ),
          for (final o in orphans.take(_orphansShown))
            _row(o.path, [o.bucket, formatBytes(o.bytes)]),
          if (orphans.length > _orphansShown)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '+${_n(orphans.length - _orphansShown)} more',
                style: muted,
              ),
            ),
        ]),
      ],
    ];
  }

  /// The biggest orphaned files listed; the rest are counted.
  static const _orphansShown = 20;

  /// A number in big type, counting up, with a line about it underneath.
  Widget _countTile({
    required String label,
    required int value,
    required String note,
  }) => DashboardTile(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AnimatedBuilder(
          animation: _intro,
          builder: (context, _) => BigNumber(
            label: label,
            value: (value * dashboardCountUp.transform(_intro.value)).round(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          style: TextStyle(fontSize: 12, color: context.colors.mutedText),
        ),
      ],
    ),
  );

  /// 1234567 as "1,234,567".
  static String _n(int n) =>
      n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

  /// A size in big type, counting up, with a line about it underneath.
  Widget _bigTile({
    required String label,
    required int bytes,
    required String note,
  }) => DashboardTile(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AnimatedBuilder(
          animation: _intro,
          builder: (context, _) => BigNumber(
            label: label,
            value: (bytes * dashboardCountUp.transform(_intro.value)).round(),
            format: formatBytes,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          style: TextStyle(fontSize: 12, color: context.colors.mutedText),
        ),
      ],
    ),
  );

  /// Rows boxed together on the card shade, square, like the list view.
  /// Without [top], no top border: it sits right under tiles whose bottom
  /// border is already there.
  Widget _list(List<Widget> rows, {bool top = true}) {
    final line = BorderSide(color: context.colors.cardBorder);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.card,
        border: top
            ? Border.fromBorderSide(line)
            : Border(left: line, right: line, bottom: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: context.colors.cardBorder),
            row,
          ],
        ],
      ),
    );
  }

  /// A name, then [cells] in columns [_cellWidth] wide, centred in them
  /// (the headings too, over their data); the last one in full text, the
  /// others muted. A [header] row is all
  /// muted and smaller: it names the columns.
  Widget _row(String name, List<String> cells, {bool header = false}) {
    final colors = context.colors;
    const figures = [FontFeature.tabularFigures()];
    TextStyle style({required bool strong}) => TextStyle(
      fontSize: header ? 11.5 : (strong ? 13 : 12),
      color: header || !strong ? colors.mutedText : colors.text,
      fontFeatures: figures,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 7 : 9),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: header
                  ? style(strong: false)
                  : TextStyle(fontSize: 13, color: colors.text),
            ),
          ),
          for (final (i, cell) in cells.indexed)
            SizedBox(
              width: _cellWidth,
              child: Text(
                cell,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style(strong: i == cells.length - 1),
              ),
            ),
        ],
      ),
    );
  }

  static const _cellWidth = 96.0;
}
