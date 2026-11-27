import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'form_buttons.dart';
import 'task.dart';
import '../files/arriving_file.dart';

/// Opens [file] in its own app (a PDF in Preview, say).
Future<void> openInDefaultApp(File file) => launchUrl(Uri.file(file.path));

/// Asks where to save a copy of [attachment] (named as it was picked),
/// then copies [file] there.
Future<void> downloadAttachment(Attachment attachment, File file) async {
  final location = await getSaveLocation(suggestedName: attachment.name);
  if (location == null) return; // Cancelled.
  await file.copy(location.path);
}

/// A task's attachments as a grid of square tiles, three to a row, with an
/// Add tile at the end. Images show as pictures and open in a viewer;
/// other files (PDFs) show their name and open in their app. Hovering a
/// tile shows Download; while [editing], each shows a ✕ to remove it.
class AttachmentGrid extends StatelessWidget {
  const AttachmentGrid({
    super.key,
    required this.attachments,
    required this.fileOf,
    required this.onAdd,
    required this.onRemove,
    this.editing = false,
  });

  final List<Attachment> attachments;

  /// Removing: every tile shows a ✕ (and no Download).
  final bool editing;

  /// Where an attachment's copy is on disk.
  final File Function(Attachment) fileOf;

  final VoidCallback onAdd;
  final ValueChanged<Attachment> onRemove;

  /// Tiles to a row, across the form (the upload tile is one too).
  static const _columns = 8;
  static const _gap = 8.0;

  void _open(BuildContext context, Attachment a) {
    if (!a.isImage) {
      openInDefaultApp(fileOf(a));
      return;
    }
    final images = attachments.where((x) => x.isImage).toList();
    showAttachmentViewer(
      context,
      images: images,
      index: images.indexOf(a),
      fileOf: fileOf,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final side = (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
      return Wrap(
        spacing: _gap,
        runSpacing: _gap,
        children: [
          for (final a in attachments)
            SizedBox.square(
              dimension: side,
              child: _AttachmentTile(
                attachment: a,
                file: fileOf(a),
                onOpen: () => _open(context, a),
                editing: editing,
                onRemove: () => onRemove(a),
              ),
            ),
          // Last in the grid, the size of a tile.
          SizedBox.square(
            dimension: side,
            child: _UploadArea(onPressed: onAdd),
          ),
        ],
      );
    },
  );
}

/// The upload tile after the attachments: a dashed outline and the
/// paperclip.
class _UploadArea extends StatelessWidget {
  const _UploadArea({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Add images or PDFs',
    waitDuration: const Duration(milliseconds: 600),
    child: CustomPaint(
      foregroundPainter: DashedBorder(context.colors.formBorder),
      child: SizedBox.expand(
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: formRadius),
            padding: EdgeInsets.zero,
            foregroundColor: context.colors.placeholder,
            overlayColor: context.colors.text,
          ),
          // Just the paperclip: the tiles are small (the tooltip says
          // what it's for).
          child: const Icon(Symbols.attach_file, size: 18),
        ),
      ),
    ),
  );
}

/// A dashed 1px outline with the app's corner radius, for upload areas
/// (as a [CustomPaint.foregroundPainter]).
class DashedBorder extends CustomPainter {
  const DashedBorder(this.color);
  final Color color;

  static const _dash = 5.0, _space = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final outline = Path()
      ..addRRect(formRadius.toRRect(Offset.zero & size).deflate(0.5));
    for (final metric in outline.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _space) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorder old) => old.color != color;
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.file,
    required this.onOpen,
    required this.onRemove,
    required this.editing,
  });

  final Attachment attachment;
  final bool editing;
  final File file;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _hover = false;

  /// The pointer is on the ✕: the tile is outlined red, to show what
  /// goes.
  bool _removeHover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.attachment;
    final content = a.isImage
        ? ArrivingFile(
            file: widget.file,
            builder: (context) => Image.file(
              widget.file,
              fit: BoxFit.cover,
              cacheWidth: 400,
              frameBuilder: (_, child, frame, syncLoaded) =>
                  frame == null && !syncLoaded
                  ? ColoredBox(color: context.colors.hover)
                  : child,
              errorBuilder: (_, _, _) => _missing(context),
            ),
          )
        : _document(context, a);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tooltip(
        message: a.name,
        waitDuration: const Duration(milliseconds: 600),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(borderRadius: formRadius, child: content),
            // The outline, over the picture's edge; the open click.
            Material(
              type: MaterialType.transparency,
              shape: RoundedRectangleBorder(
                borderRadius: formRadius,
                side: widget.editing && _removeHover
                    ? BorderSide(color: deleteColor, width: 2)
                    : BorderSide(color: context.colors.formBorder),
              ),
              child: InkWell(
                customBorder: formShape,
                onTap: widget.onOpen,
                mouseCursor: SystemMouseCursors.click,
              ),
            ),
            // Editing: a ✕ on every tile. Otherwise Download, on hover.
            if (widget.editing)
              Positioned(
                top: 3,
                right: 3,
                // Red, with dark ✕, like the delete buttons.
                child: MouseRegion(
                  onEnter: (_) => setState(() => _removeHover = true),
                  onExit: (_) => setState(() => _removeHover = false),
                  child: _overlayButton(
                    'Remove',
                    Symbols.close,
                    widget.onRemove,
                    fill: deleteColor,
                    iconColor: accentText,
                  ),
                ),
              )
            else if (_hover)
              Positioned(
                top: 3,
                right: 3,
                child: _overlayButton(
                  'Download',
                  Symbols.download,
                  () => downloadAttachment(widget.attachment, widget.file),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// A small square button over the tile's corner.
  Widget _overlayButton(
    String tooltip,
    IconData icon,
    VoidCallback onTap, {
    Color? fill,
    Color? iconColor,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: fill ?? context.colors.divider,
      shape: formShape,
      child: InkWell(
        customBorder: formShape,
        onTap: onTap,
        // Small, for the small tiles.
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 12, color: iconColor ?? context.colors.text),
        ),
      ),
    ),
  );

  /// A document's tile: its file type in letters ("PDF", "DOCX", "XLSX",
  /// "TXT"), clearer at this size than an icon; a document icon only when
  /// the file has no extension. Its name shows on hover; the tiles are too
  /// small for it.
  Widget _document(BuildContext context, Attachment a) => ColoredBox(
    color: context.colors.hover,
    child: Center(
      child: a.extension.isEmpty
          ? Icon(Symbols.draft, size: 20, color: context.colors.text)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // A long extension shrinks to fit rather than wrapping.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  a.extension.toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                    color: context.colors.text,
                  ),
                ),
              ),
            ),
    ),
  );

  Widget _missing(BuildContext context) => ColoredBox(
    color: context.colors.hover,
    child: Center(
      child: Icon(Symbols.broken_image, color: context.colors.mutedText),
    ),
  );
}

/// Shows [images] in a modal, starting at [index]: one at a time, as big
/// as the window allows, with ← → (buttons or keys) between them. Escape,
/// ✕ or a click outside the picture closes it.
Future<void> showAttachmentViewer(
  BuildContext context, {
  required List<Attachment> images,
  required int index,
  required File Function(Attachment) fileOf,
}) => showDialog(
  context: context,
  barrierColor: Colors.black87,
  builder: (_) =>
      _AttachmentViewer(images: images, index: index, fileOf: fileOf),
);

class _AttachmentViewer extends StatefulWidget {
  const _AttachmentViewer({
    required this.images,
    required this.index,
    required this.fileOf,
  });

  final List<Attachment> images;
  final int index;
  final File Function(Attachment) fileOf;

  @override
  State<_AttachmentViewer> createState() => _AttachmentViewerState();
}

class _AttachmentViewerState extends State<_AttachmentViewer> {
  late int _index = widget.index.clamp(0, widget.images.length - 1);

  bool get _many => widget.images.length > 1;

  void _step(int by) =>
      setState(() => _index = (_index + by) % widget.images.length);

  Widget _button(String tooltip, IconData icon, VoidCallback onPressed) =>
      Tooltip(
        message: tooltip,
        child: Material(
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: formRadius,
            side: BorderSide(color: context.colors.formBorder),
          ),
          child: InkWell(
            customBorder: formShape,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 18, color: context.colors.text),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final image = widget.images[_index];
    final file = widget.fileOf(image);
    return CallbackShortcuts(
      bindings: {
        if (_many) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _step(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _step(1),
        },
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // A click anywhere but the picture closes it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(72, 64, 72, 40),
                child: Center(
                  child: GestureDetector(
                    // Clicking the picture itself keeps it open.
                    onTap: () {},
                    child: ClipRRect(
                      borderRadius: formRadius,
                      child: ArrivingFile(
                        file: file,
                        builder: (context) => Image.file(
                          file,
                          key: ValueKey(image.file),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          errorBuilder: (_, _, _) => Icon(
                            Symbols.broken_image,
                            size: 48,
                            color: context.colors.mutedText,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Its name (and place among them), Open, and ✕ along the top.
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                spacing: 8,
                children: [
                  // All the room the buttons don't use, the name at its
                  // left: the buttons sit right at the edge. (A Spacer
                  // beside a Flexible got half the room, pulling them in.)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: formRadius,
                          border: Border.all(color: context.colors.formBorder),
                        ),
                        child: Text(
                          _many
                              ? '${image.name}  ·  ${_index + 1} of '
                                    '${widget.images.length}'
                              : image.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _button(
                    'Download',
                    Symbols.download,
                    () => downloadAttachment(image, file),
                  ),
                  _button(
                    'Open in default app',
                    Symbols.open_in_new,
                    () => openInDefaultApp(file),
                  ),
                  _button('Close', Symbols.close, () => Navigator.pop(context)),
                ],
              ),
            ),
            if (_many) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _button(
                    'Previous',
                    Symbols.chevron_left,
                    () => _step(-1),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _button('Next', Symbols.chevron_right, () => _step(1)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
