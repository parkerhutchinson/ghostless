import 'dart:async';

/// Events from every one of [streams], as they come. Cancelling cancels
/// them all. (For watching several store collections at once.)
Stream<T> mergeStreams<T>(List<Stream<T>> streams) {
  late final StreamController<T> controller;
  final subscriptions = <StreamSubscription<T>>[];
  controller = StreamController<T>(
    onListen: () {
      for (final s in streams) {
        subscriptions.add(
          s.listen(controller.add, onError: controller.addError),
        );
      }
    },
    onPause: () {
      for (final s in subscriptions) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subscriptions) {
        s.resume();
      }
    },
    onCancel: () => Future.wait(subscriptions.map((s) => s.cancel())),
  );
  return controller.stream;
}
