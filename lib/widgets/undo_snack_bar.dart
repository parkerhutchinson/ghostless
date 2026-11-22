import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_theme.dart';
import '../layout.dart';

/// How long an Undo snack bar stays up.
const undoSnackBarDuration = Duration(seconds: 10);

/// Shows [message] with an Undo button and a close (✕) button, replacing any
/// current snack bar. Used for deletions and dismissals.
/// The returned controller's `closed` says whether Undo was pressed.
///
/// It slides up from below the window and back down when it goes (after
/// [undoSnackBarDuration], or Undo / ✕). Only the full-width ("fixed")
/// snack bar slides; the floating one cuts out. So this is a fixed one with
/// no fill of its own, carrying a centered accent box as its content.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.fixed,
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      // Clicks beside the box reach the app below.
      hitTestBehavior: HitTestBehavior.deferToChild,
      duration: undoSnackBarDuration,
      persist: false,
      content: _UndoToast(
        message: message,
        onUndo: () {
          onUndo();
          messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.action);
        },
        onClose: () =>
            messenger.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss),
      ),
    ),
  );
}

/// The toast: message, Undo and ✕ on the accent, with a lighter fill
/// growing left to right as its time runs out.
class _UndoToast extends StatefulWidget {
  const _UndoToast({
    required this.message,
    required this.onUndo,
    required this.onClose,
  });
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onClose;

  @override
  State<_UndoToast> createState() => _UndoToastState();
}

class _UndoToastState extends State<_UndoToast>
    with SingleTickerProviderStateMixin {
  late final _countdown = AnimationController(
    vsync: this,
    duration: undoSnackBarDuration,
  )..forward();

  @override
  void dispose() {
    _countdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The accent with white text and buttons (dark on a light accent).
    final on = scheme.onPrimary;
    // Centered in the pane right of the sidebar, not the whole window.
    return Padding(
      padding: const EdgeInsets.only(left: sidebarWidth),
      child: Center(
        child: Container(
          width: 380,
          margin: const EdgeInsets.only(bottom: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: formRadius,
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12)],
          ),
          child: Stack(
            children: [
              // Time running out: fills from the left, full when it goes.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _countdown,
                  builder: (context, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _countdown.value,
                    child: ColoredBox(color: on.withValues(alpha: 0.18)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          widget.message,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: on, fontSize: 14),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onUndo,
                      style: TextButton.styleFrom(foregroundColor: on),
                      child: const Text('Undo'),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      tooltip: 'Close',
                      iconSize: 18,
                      icon: Icon(Symbols.close, color: on),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
