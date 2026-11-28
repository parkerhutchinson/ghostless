import 'package:material_ui/material_ui.dart';

import '../layout.dart';

/// Opens a dialog centered in the view pane (right of the sidebar), not
/// the whole window: every modal opened from inside a view pane (a
/// project's board, list or dashboard, Activity, Company...) uses this.
/// The backdrop still dims the whole window. See CLAUDE.md, "Modals from
/// a view center in its pane".
///
/// [inPane] false centers it in the window instead, for a dialog shared
/// with the sidebar (the project dialog) when the sidebar opens it.
Future<T?> showPaneDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color barrierColor = Colors.black54,
  bool barrierDismissible = true,
  bool inPane = true,
}) => showDialog<T>(
  context: context,
  barrierColor: barrierColor,
  barrierDismissible: barrierDismissible,
  builder: (context) => Padding(
    padding: EdgeInsets.only(left: inPane ? sidebarWidth : 0),
    child: Builder(builder: builder),
  ),
);
