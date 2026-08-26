/// Helpers for the cumulative snapshots the model emits.
extension LoadingStreamDeltas on Stream<String> {
  /// Converts cumulative snapshots into incremental deltas.
  ///
  /// `stream` emits the whole response each time, which suits assigning to UI
  /// state but not appending to a buffer or writing to a socket. This does the
  /// subtraction for you:
  ///
  /// ```dart
  /// await for (final chunk in session.stream(prompt).deltas()) {
  ///   stdout.write(chunk);
  /// }
  /// ```
  ///
  /// A snapshot that is not an extension of the previous one — a rare
  /// correction mid-generation — is emitted whole rather than diffed, so the
  /// concatenation always ends up correct.
  Stream<String> deltas() async* {
    var previous = '';
    await for (final String snapshot in this) {
      if (snapshot.startsWith(previous)) {
        final String delta = snapshot.substring(previous.length);
        if (delta.isNotEmpty) yield delta;
      } else {
        yield snapshot;
      }
      previous = snapshot;
    }
  }
}
