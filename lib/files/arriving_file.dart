import 'dart:io';

import 'package:material_ui/material_ui.dart';

/// Goes up each time files arrive from online storage (see `FileSync`).
final fileArrivals = ValueNotifier<int>(0);

/// Shows [builder]'s widget for a local [file] that may not be on this Mac
/// yet (another Mac added it, and it's still on its way). Once it
/// arrives, the widget is built afresh, so an `Image.file` that showed its
/// placeholder loads it (an image widget doesn't try again by itself).
class ArrivingFile extends StatelessWidget {
  const ArrivingFile({super.key, required this.file, required this.builder});
  final File file;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: fileArrivals,
    builder: (context, _, _) => KeyedSubtree(
      // A new key when it turns up: a new image widget, which loads it.
      key: ValueKey((file.path, file.existsSync())),
      child: builder(context),
    ),
  );
}
