import 'package:material_ui/material_ui.dart';

/// Builds from a stream of stored data (a repository's `watch()`),
/// starting from its value now (`current()`). Unlike a [StreamBuilder]
/// given `stream: repo.watch(), initialData: repo.current()` in a build
/// method, both are called only once, when it's first built: a new
/// stream each build makes the builder unsubscribe and subscribe again,
/// and reading the store each build decodes every record (with thousands
/// of tasks, a stall on every rebuild). Give it a [key] when what it
/// watches changes (a task's comments: `ValueKey(taskId)`), to start over.
class Watched<T> extends StatefulWidget {
  const Watched({
    super.key,
    required this.watch,
    required this.current,
    required this.builder,
  });

  final Stream<T> Function() watch;
  final T Function() current;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<Watched<T>> createState() => _WatchedState<T>();
}

class _WatchedState<T> extends State<Watched<T>> {
  late final Stream<T> _stream = widget.watch();
  late final T _first = widget.current();

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: _stream,
    initialData: _first,
    builder: (context, snap) => widget.builder(context, snap.data as T),
  );
}
