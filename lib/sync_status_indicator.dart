import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'sync/sync_service.dart';
import 'widgets/watched.dart';

/// Small icon next to Settings (at the bottom of the sidebar) showing
/// whether local data has reached the server; hover it for the details.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, required this.sync});

  /// The connection picked in Settings; local-only without one.
  final SyncService sync;

  @override
  Widget build(BuildContext context) => Watched<SyncConnection?>(
    watch: sync.watch,
    current: () => sync.current,
    builder: (context, connection) => switch (connection) {
      null => const _Status(Symbols.cloud_off, 'Local only'),
      final c => _connected(c.controller, c.config.kind.label),
    },
  );

  Widget _connected(SyncController sync, String name) {
    return StreamBuilder<SyncStatus>(
      // Keyed so a new connection gets a fresh subscription.
      key: ObjectKey(sync),
      stream: sync.statusStream,
      initialData: sync.status,
      builder: (context, snapshot) {
        final s = snapshot.requireData;
        final pending = s.pending > 0 ? ' · ${s.pending} pending' : '';
        return switch (s.phase) {
          SyncPhase.syncing => _Status(
            Symbols.sync,
            'Syncing with $name…$pending',
          ),
          SyncPhase.offline => _Status(
            Symbols.cloud_off,
            'Can’t reach $name$pending\n'
            '${retrying(s.retryIn)}\n${s.lastError}',
          ),
          SyncPhase.idle => _Status(
            pending.isEmpty ? Symbols.cloud_done : Symbols.cloud_upload,
            pending.isEmpty ? 'Synced with $name' : 'Waiting$pending',
          ),
        };
      },
    );
  }
}

/// Just the icon; [message] shows in a tooltip on hover.
class _Status extends StatelessWidget {
  const _Status(this.icon, this.message);
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: message,
    // Padding gives the pointer a slightly bigger target than the icon.
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 16, color: context.colors.text),
    ),
  );
}
