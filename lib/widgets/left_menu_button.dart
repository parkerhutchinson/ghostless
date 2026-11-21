import 'package:material_ui/material_ui.dart';

/// A ⋯ button whose menu always opens to the left: the menu's right edge
/// lines up with the button's, and it grows out from that corner.
///
/// [PopupMenuButton] instead picks a side from where the button is in the
/// window (left half: opens right; right half: opens left), so menus on
/// the board opened in different directions.
class LeftMenuButton<T> extends StatelessWidget {
  const LeftMenuButton({
    super.key,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.style,
    this.iconSize,
    this.padding,
    this.tooltip,
    this.constraints,
    this.onOpened,
    this.onCanceled,
  });

  final Widget icon;
  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final ButtonStyle? style;
  final double? iconSize;
  final EdgeInsetsGeometry? padding;
  final String? tooltip;
  final BoxConstraints? constraints;
  final VoidCallback? onOpened;
  final VoidCallback? onCanceled;

  Future<void> _open(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = Rect.fromPoints(
      button.localToGlobal(Offset.zero, ancestor: overlay),
      button.localToGlobal(
        button.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    );
    final size = overlay.size;
    onOpened?.call();
    final value = await showMenu<T>(
      context: context,
      constraints: constraints,
      // The menu layout right-aligns to `right` whenever `left` is the
      // bigger of the two, so `left` is set to the full width.
      position: RelativeRect.fromLTRB(
        size.width,
        rect.top,
        size.width - rect.right,
        size.height - rect.bottom,
      ),
      items: itemBuilder(context),
    );
    if (!context.mounted) return;
    if (value == null) {
      onCanceled?.call();
    } else {
      onSelected(value);
    }
  }

  @override
  Widget build(BuildContext context) => Builder(
    // Its own context, so the menu is placed against this button's box.
    builder: (context) => IconButton(
      tooltip: tooltip,
      iconSize: iconSize,
      padding: padding,
      style: style,
      icon: icon,
      onPressed: () => _open(context),
    ),
  );
}
