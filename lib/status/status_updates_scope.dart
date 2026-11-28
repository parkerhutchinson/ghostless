import 'package:material_ui/material_ui.dart';

import 'status_update.dart';

/// The status update store, for the status dialog and the dashboards.
/// Sits above the app's navigator (like [CommentsScope]), so dialogs see
/// it.
class StatusUpdatesScope extends InheritedWidget {
  const StatusUpdatesScope({
    super.key,
    required this.repo,
    required this.me,
    required super.child,
  });

  final StatusUpdateRepository repo;

  /// The profile using the app on this Mac: who new updates are by (null
  /// before there's one).
  final String? Function() me;

  /// Null outside a scope (tests that don't set one up): no updates.
  static StatusUpdatesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StatusUpdatesScope>();

  @override
  bool updateShouldNotify(StatusUpdatesScope old) => old.repo != repo;
}
