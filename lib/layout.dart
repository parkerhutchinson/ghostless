import 'dart:ui' show Color;

/// Height of the macOS title bar strip the traffic lights sit in. The app
/// draws underneath it, so content insets itself by this much.
const titleBarHeight = 28.0;

/// Width of the project sidebar on the left; the tasks pane is the rest.
const sidebarWidth = 260.0;

/// About 82% black: the default background color, and the base for the
/// app's surfaces and borders. Widgets use
/// `context.colors` (see AppColors), which follows the chosen background.
const surfaceColor = Color(0xFF2D2D2D);
