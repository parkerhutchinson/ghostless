import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:sync_engine/sync_engine.dart';

import '../app_theme.dart';
import '../tasks/due_date.dart' show formatTime;
import 'app_schema.dart';
import 'compatibility.dart';
import 'remote_config.dart';
import 'sync_service.dart';
import '../widgets/sliding_toggle.dart';
import '../widgets/selected_text.dart';

/// The Sync section of Settings: where the app syncs to (or that it's
/// local-only), with buttons to connect, sync now, change or disconnect.
class SyncSettingsSection extends StatelessWidget {
  const SyncSettingsSection({super.key, required this.sync});
  final SyncService sync;

  @override
  Widget build(BuildContext context) => StreamBuilder<SyncConnection?>(
    stream: sync.watch(),
    initialData: sync.current,
    builder: (context, snap) {
      final connection = snap.data;
      final muted = TextStyle(fontSize: 13, color: context.colors.mutedText);
      Widget outlined(String label, VoidCallback onPressed) => OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.text,
          side: BorderSide(color: context.colors.formBorder),
        ),
        child: Text(label),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            'Sync',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: context.colors.text,
            ),
          ),
          if (connection == null)
            Text(
              'Local only: your data stays on this Mac. Connect a database '
              'to share projects and tasks with other Macs.',
              style: muted,
            )
          else
            _ConnectionStatus(connection: connection),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (connection == null)
                outlined(
                  'Connect to a database…',
                  () => showConnectDialog(context, sync),
                )
              else ...[
                outlined('Sync now', connection.controller.syncNow),
                outlined('Change…', () => showConnectDialog(context, sync)),
                TextButton(
                  onPressed: sync.disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            ],
          ),
        ],
      );
    },
  );
}

/// "Sanity · abc123 / production", and how syncing is going.
class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.connection});
  final SyncConnection connection;

  @override
  Widget build(BuildContext context) {
    final config = connection.config;
    return StreamBuilder<SyncStatus>(
      key: ObjectKey(connection),
      stream: connection.controller.statusStream,
      initialData: connection.controller.status,
      builder: (context, snap) {
        final s = snap.requireData;
        final last = s.lastSyncedAt;
        final pending = s.pending > 0 ? ' · ${s.pending} waiting to send' : '';
        final (icon, status) = switch (s.phase) {
          SyncPhase.syncing => (Symbols.sync, 'Syncing…$pending'),
          SyncPhase.offline => (
            Symbols.cloud_off,
            'Can’t reach it right now; retrying.$pending',
          ),
          SyncPhase.idle => (
            Symbols.cloud_done,
            last == null
                ? 'Connected$pending'
                : 'Synced at ${formatTime(last.hour * 60 + last.minute)}'
                      '$pending',
          ),
        };
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Icon(icon, size: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    '${config.kind.label} · ${config.description}',
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.colors.mutedText,
                    ),
                  ),
                  if (s.phase == SyncPhase.offline && s.lastError != null)
                    Text(
                      '${s.lastError}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.mutedText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Picks a database and checks it before connecting.
Future<void> showConnectDialog(BuildContext context, SyncService sync) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _ConnectDialog(sync: sync),
    );

/// One field of the connection form.
typedef _Field = ({String key, String label, String initial, bool secret});

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.sync});
  final SyncService sync;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late RemoteKind _kind = widget.sync.saved?.kind ?? RemoteKind.sanity;

  /// Every field typed so far, by kind and key, so switching kinds and
  /// back keeps what was typed.
  final _controllers = <String, TextEditingController>{};
  late bool _ssl = switch (widget.sync.saved) {
    PostgresConfig(:final ssl) => ssl,
    _ => true,
  };

  bool _checking = false;
  bool _connecting = false;
  CompatibilityReport? _report;

  /// The settings [_report] is for; editing them clears it.
  RemoteConfig? _checked;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The form's fields for [kind], prefilled from the saved settings.
  List<_Field> _fields(RemoteKind kind) {
    final saved = widget.sync.saved?.toJson() ?? const {};
    String initial(String key, [String fallback = '']) =>
        saved['kind'] == kind.name ? '${saved[key] ?? fallback}' : fallback;
    _Field f(
      String key,
      String label, {
      String fallback = '',
      bool secret = false,
    }) => (
      key: key,
      label: label,
      initial: initial(key, fallback),
      secret: secret,
    );
    return switch (kind) {
      RemoteKind.sanity => [
        f('projectId', 'Project ID'),
        f('dataset', 'Dataset', fallback: 'production'),
        f('token', 'API token (Editor access)', secret: true),
      ],
      RemoteKind.contentful => [
        f('spaceId', 'Space ID'),
        f('environment', 'Environment', fallback: 'master'),
        f('locale', 'Locale', fallback: 'en-US'),
        f('deliveryToken', 'Content Delivery API token', secret: true),
        f('managementToken', 'Content Management API token', secret: true),
      ],
      RemoteKind.postgres || RemoteKind.mysql => [
        f('host', 'Host'),
        f(
          'port',
          'Port',
          fallback: kind == RemoteKind.postgres ? '5432' : '3306',
        ),
        f('database', 'Database'),
        f('username', 'Username'),
        f('password', 'Password', secret: true),
      ],
    };
  }

  TextEditingController _controller(_Field field) => _controllers.putIfAbsent(
    '${_kind.name}.${field.key}',
    () => AppTextController(text: field.initial),
  );

  /// The settings as typed.
  RemoteConfig? get _config {
    final values = {
      'kind': _kind.name,
      for (final f in _fields(_kind)) f.key: _controller(f).text,
    };
    return RemoteConfig.fromJson({
      ...values,
      if (values['port'] case final String port) 'port': int.tryParse(port),
      'ssl': _ssl,
    });
  }

  Future<void> _check() async {
    final config = _config!;
    setState(() {
      _checking = true;
      _report = null;
    });
    final report = await widget.sync.check(config);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _report = report;
      _checked = config;
    });
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await widget.sync.connect(_checked!, _report!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final missing = config?.missing;
    final report = _report;
    final noun = switch (_kind) {
      RemoteKind.sanity => 'document type',
      RemoteKind.contentful => 'content type',
      _ => 'table',
    };
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: const Text('Connect to a database'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              SlidingToggle<RemoteKind>(
                segments: [
                  for (final k in RemoteKind.values)
                    ToggleSegment(value: k, label: k.label),
                ],
                selected: _kind,
                onChanged: (k) => setState(() {
                  _kind = k;
                  _report = null;
                }),
              ),
              Text(
                'The database needs a $noun for each of '
                '${appSchema.keys.map((c) => '“$c”').join(', ')}, with '
                'fields named like the app’s. Check connection tests that '
                'it fits before anything is synced.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.colors.mutedText,
                ),
              ),
              for (final f in _fields(_kind))
                TextField(
                  key: ValueKey('${_kind.name}.${f.key}'),
                  controller: _controller(f),
                  obscureText: f.secret,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: const TextStyle(fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: f.label,
                    labelStyle: TextStyle(color: context.colors.mutedText),
                    contentPadding: const EdgeInsets.all(12),
                    enabledBorder: context.colors.fieldBorder,
                    border: context.colors.fieldBorder,
                  ),
                  // Changed settings need checking again.
                  onChanged: (_) => setState(() => _report = null),
                ),
              if (_kind == RemoteKind.postgres)
                CheckboxListTile(
                  value: _ssl,
                  onChanged: (v) => setState(() {
                    _ssl = v ?? true;
                    _report = null;
                  }),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Require an encrypted (SSL) connection'),
                ),
              Text(
                'These settings, passwords and tokens included, are kept on '
                'this Mac only.',
                style: TextStyle(fontSize: 12, color: context.colors.mutedText),
              ),
              if (_checking)
                const Row(
                  spacing: 10,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    Text('Checking the database…'),
                  ],
                )
              else if (report != null)
                _ReportView(report: report),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: missing == null && !_checking && !_connecting
              ? _check
              : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.colors.text,
            side: BorderSide(color: context.colors.formBorder),
          ),
          child: Text(
            missing == null ? 'Check connection' : 'Enter the $missing',
          ),
        ),
        FilledButton(
          onPressed: report != null && report.compatible && !_connecting
              ? _connect
              : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// The check's findings, grouped by collection.
class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});
  final CompatibilityReport report;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.mutedText;
    final error = Colors.red.shade300;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: formRadius,
        border: Border.all(color: context.colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            report.compatible
                ? 'This database works with the app.'
                : 'This database doesn’t fit the app yet.',
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
          for (final r in report.results)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Icon(
                  switch (r.level) {
                    CheckLevel.passed => Symbols.check_circle,
                    CheckLevel.warning => Symbols.warning,
                    CheckLevel.error => Symbols.error,
                  },
                  size: 16,
                  color: r.level == CheckLevel.error ? error : null,
                ),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 12.5),
                      children: [
                        if (r.collection case final c?)
                          TextSpan(
                            text: '$c  ',
                            style: const TextStyle(fontWeight: FontWeight.w400),
                          ),
                        TextSpan(text: r.message),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          if (report.compatible)
            Text(
              'Connecting merges this Mac’s data with the database’s: '
              'records on either side are copied to the other, and the '
              'newer change wins where both changed.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
        ],
      ),
    );
  }
}
