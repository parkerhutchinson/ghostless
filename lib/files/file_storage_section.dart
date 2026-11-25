import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../app_theme.dart';
import '../sync/remote_config.dart';
import '../sync/sync_service.dart';
import '../tasks/due_date.dart' show formatTime;
import '../widgets/selected_text.dart';
import 'file_storage.dart';
import 'file_sync.dart';

/// The Files section of Settings › Data: whether images, attachments and
/// photos are kept online (Supabase Storage) so every Mac has them, with
/// buttons to connect, sync now, change or disconnect.
class FileStorageSection extends StatelessWidget {
  const FileStorageSection({super.key, required this.files, this.sync});
  final FileSync files;

  /// The database connection: its Supabase username fills in the project
  /// URL.
  final SyncService? sync;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: files.status,
    builder: (context, status, _) {
      final config = files.config;
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
            'Files',
            style: TextStyle(fontSize: 12, color: context.colors.text),
          ),
          if (config == null)
            Text(
              'Images, attachments and photos stay on this Mac. Connect '
              'Supabase Storage to share them with other Macs (the '
              'database only shares their names).',
              style: muted,
            )
          else
            _Status(config: config, status: status),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (config == null)
                outlined(
                  'Connect file storage…',
                  () => _showConnect(context, files, sync),
                )
              else ...[
                outlined('Sync files now', files.syncNow),
                outlined('Change…', () => _showConnect(context, files, sync)),
                TextButton(
                  onPressed: files.disconnect,
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

/// "abcd.supabase.co / files", and how it's going.
class _Status extends StatelessWidget {
  const _Status({required this.config, required this.status});
  final StorageConfig config;
  final FileSyncStatus status;

  @override
  Widget build(BuildContext context) {
    final last = status.lastSyncedAt;
    final notes = [
      if (status.waiting > 0)
        '${status.waiting} waiting for another Mac to send '
            '${status.waiting == 1 ? 'it' : 'them'}',
      if (status.tooLarge > 0)
        '${status.tooLarge} too big to send '
            '(over the bucket’s size limit)',
    ].map((n) => ' · $n').join();
    final (icon, text) = switch (status.phase) {
      FileSyncPhase.syncing => (Symbols.sync, 'Syncing files…'),
      FileSyncPhase.offline => (
        Symbols.cloud_off,
        status.error ?? 'Can’t reach it right now; retrying.',
      ),
      FileSyncPhase.idle => (
        Symbols.cloud_done,
        last == null
            ? 'Connected$notes'
            : 'Files synced at ${formatTime(last.hour * 60 + last.minute)}'
                  '$notes',
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
                'Supabase Storage · ${config.description}',
                style: const TextStyle(fontSize: 13.5),
              ),
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.colors.mutedText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _showConnect(
  BuildContext context,
  FileSync files,
  SyncService? sync,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black54,
  builder: (_) => _ConnectDialog(
    files: files,
    // From the database's username (postgres.<ref>), when it's Supabase.
    suggestedUrl: switch (sync?.current?.config) {
      final PostgresConfig db => StorageConfig.urlFromDatabaseUser(
        db.username,
      ),
      _ => null,
    },
  ),
);

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.files, this.suggestedUrl});
  final FileSync files;
  final String? suggestedUrl;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late final StorageConfig? _old = widget.files.config;
  late final _url = AppTextController(
    text: _old?.url ?? widget.suggestedUrl ?? '',
  );
  late final _key = AppTextController(text: _old?.key ?? '');
  late final _bucket = AppTextController(
    text: _old?.bucket ?? StorageConfig.defaultBucket,
  );

  bool _checking = false, _connecting = false;

  /// What the last check found: null before one, '' when it worked.
  String? _result;
  StorageConfig? _checked;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _bucket.dispose();
    super.dispose();
  }

  StorageConfig get _config => StorageConfig(
    url: _url.text.trim(),
    key: _key.text.trim(),
    bucket: _bucket.text.trim(),
  );

  Future<void> _check() async {
    final config = _config;
    setState(() {
      _checking = true;
      _result = null;
    });
    final storage = SupabaseStorage(config);
    String result;
    try {
      await storage.check();
      result = '';
    } on FileStorageException catch (e) {
      result = e.message;
    } catch (e) {
      result = '$e';
    } finally {
      storage.close();
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = result;
      _checked = config;
    });
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    final done = widget.files.connect(_checked!);
    if (mounted) Navigator.pop(context);
    await done;
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool secret = false,
  }) => TextField(
    controller: controller,
    obscureText: secret,
    autocorrect: false,
    enableSuggestions: false,
    style: const TextStyle(fontSize: 13.5),
    decoration: InputDecoration(
      isDense: true,
      labelText: label,
      labelStyle: TextStyle(color: context.colors.mutedText),
      contentPadding: const EdgeInsets.all(12),
      enabledBorder: context.colors.fieldBorder,
      border: context.colors.fieldBorder,
    ),
    // Changed settings need checking again.
    onChanged: (_) => setState(() => _result = null),
  );

  @override
  Widget build(BuildContext context) {
    final missing = _config.missing;
    final result = _result;
    final muted = TextStyle(fontSize: 12.5, color: context.colors.mutedText);
    return AlertDialog(
      backgroundColor: context.colors.surface,
      shape: formShape,
      title: const Text('Connect file storage'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Text(
                'Supabase Storage keeps images, attachments, profile photos '
                'and backgrounds online, so every Mac has them. In the '
                'Supabase dashboard: the project URL is under Project '
                'Settings › Data API, the secret key under Project '
                'Settings › API Keys.',
                style: muted,
              ),
              _field(_url, 'Project URL'),
              _field(_key, 'Secret key', secret: true),
              _field(_bucket, 'Bucket'),
              Text(
                'The secret key can read and write everything in the '
                'project: it’s kept on this Mac only, never synced.',
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
                    Text('Checking storage…'),
                  ],
                )
              else if (result != null)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    Icon(
                      result.isEmpty ? Symbols.check_circle : Symbols.error,
                      size: 18,
                      color: result.isEmpty
                          ? context.colors.text
                          : Colors.red.shade300,
                    ),
                    Expanded(
                      child: Text(
                        result.isEmpty
                            ? 'It works: a test file was written, read back '
                                  'and deleted.'
                            : result,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
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
          onPressed: result == '' && _checked == _config && !_connecting
              ? _connect
              : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
