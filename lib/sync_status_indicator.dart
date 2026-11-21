import 'package:material_ui/material_ui.dart';
import 'package:sync_engine/sync_engine.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';

/// Small title-bar icon showing whether local data has reached the
/// server; hover it for the details.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key, required this.sync});

  /// Null when the app runs local-only.
  final SyncController? sync;

  @override
  Widget build(BuildContext context) {
    final sync = this.sync;
    if (sync == null) return const _Status(Symbols.cloud_off, 'Local only');
    return StreamBuilder<SyncStatus>(
      stream: sync.statusStream,
      initialData: sync.status,
      builder: (context, snapshot) {
        final s = snapshot.requireData;
        final pending = s.pending > 0 ? ' · ${s.pending} pending' : '';
        return switch (s.phase) {
          SyncPhase.syncing => _Status(Symbols.sync, 'Syncing…$pending'),
          SyncPhase.offline => _Status(
            Symbols.cloud_off,
            'Offline$pending\n${s.lastError}',
          ),
          SyncPhase.idle => _Status(
            pending.isEmpty ? Symbols.cloud_done : Symbols.cloud_upload,
            pending.isEmpty ? 'Synced' : 'Waiting$pending',
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
