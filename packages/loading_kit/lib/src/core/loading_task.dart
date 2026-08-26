import 'dart:async';

import 'loading_exceptions.dart';
import 'loading_handle.dart';

/// The control surface handed to the body of [LoadingController.runTask].
///
/// It lets long-running work report progress back to the overlay and observe
/// whether the user has asked to cancel:
///
/// ```dart
/// await Loading.runTask((task) async {
///   for (var i = 0; i < files.length; i++) {
///     task.throwIfCancelled();
///     task.report((i + 1) / files.length, message: 'Uploading ${i + 1}…');
///     await upload(files[i]);
///   }
/// }, cancelAfter: const Duration(seconds: 3));
/// ```
class LoadingTask {
  /// Wraps [handle]. Created by the controller, not by user code.
  LoadingTask(this._handle);

  final LoadingHandle _handle;
  final Completer<void> _cancelled = Completer<void>();

  /// Whether the user has requested cancellation.
  ///
  /// Cancellation is cooperative: the overlay stops, but the work keeps
  /// running until the body checks this flag or calls [throwIfCancelled].
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when the user requests cancellation. Never completes otherwise.
  Future<void> get onCancelled => _cancelled.future;

  /// Throws [LoadingCancelled] if the user has requested cancellation.
  ///
  /// Call this between steps of a multi-part job to make it interruptible.
  void throwIfCancelled() {
    if (isCancelled) throw const LoadingCancelled();
  }

  /// Reports determinate [progress] between 0.0 and 1.0, with optional text.
  ///
  /// Pass null to return the indicator to an indeterminate spin.
  void report(double? progress, {String? message, String? detail}) {
    _handle.update(
      progress: progress,
      message: message,
      detail: detail,
      clearProgress: progress == null,
    );
  }

  /// Replaces the primary message without touching progress.
  set message(String? value) => _handle.message = value;

  /// Marks the task cancelled. Invoked by the controller when the user taps
  /// the cancel affordance.
  void markCancelled() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}
