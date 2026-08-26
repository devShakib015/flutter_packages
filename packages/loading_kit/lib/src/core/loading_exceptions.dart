/// Thrown into a task when the user cancels it from the overlay.
///
/// Caught by `LoadingController.run`, which rethrows it so callers can
/// distinguish a cancellation from a genuine failure:
///
/// ```dart
/// try {
///   await Loading.run(fetch, cancelAfter: const Duration(seconds: 5));
/// } on LoadingCancelled {
///   // User backed out. Not an error worth reporting.
/// }
/// ```
class LoadingCancelled implements Exception {
  /// Creates a cancellation signal, optionally naming the cancelled work.
  const LoadingCancelled([this.message]);

  /// An optional human-readable description of what was cancelled.
  final String? message;

  @override
  String toString() =>
      message == null ? 'LoadingCancelled' : 'LoadingCancelled: $message';
}

/// Thrown when the global [Loading] facade is used before a host is installed.
///
/// Install one by passing `LoadingKit.builder()` to `MaterialApp.builder`.
class LoadingHostMissing extends Error {
  @override
  String toString() => '''
loading_kit: no host is installed, so the global `Loading` facade has nothing
to drive.

Add the builder to your app:

  MaterialApp(
    builder: LoadingKit.builder(),
    home: const HomePage(),
  )

If you are driving a scoped controller instead, use `context.loading` or your
own `LoadingController` rather than the global facade.''';
}
