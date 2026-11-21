import 'package:material_ui/material_ui.dart';

/// Shows [message] with an Undo button and a close (✕) button, replacing any
/// current snack bar. Only used for deletions.
/// The returned controller's `closed` says whether Undo was pressed.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showUndoSnackBar(
  BuildContext context,
  String message, {
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: 380,
      content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
      action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      showCloseIcon: true,
    ),
  );
}
