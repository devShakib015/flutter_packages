import 'dart:async';

import 'loading_controller.dart';
import 'loading_operation.dart';
import 'loading_status.dart';
import 'loading_timing.dart';

/// A live reference to one operation shown by a [LoadingController].
///
/// Returned by [LoadingController.show]. Use it to report progress, swap the
/// message, or retire the operation with success, error, or a plain dismiss:
///
/// ```dart
/// final upload = Loading.show(message: 'Uploading…', progress: 0);
/// upload.progress = 0.4;
/// upload.update(detail: '2 of 5 files');
/// await upload.success('Uploaded');
/// ```
///
/// Retiring is idempotent — calling [dismiss] twice is harmless, and the
/// second call simply returns the same completion future.
class LoadingHandle {
  /// Wraps [operation] belonging to [controller]. Created by the controller.
  LoadingHandle(this._controller, this._operation);

  final LoadingController _controller;
  final LoadingOperation _operation;

  /// The operation this handle drives. Internal to the package.
  LoadingOperation get operation => _operation;

  /// Whether the operation is still tracked by its controller.
  bool get isActive => !_operation.removed;

  /// Whether the operation has passed its reveal delay and is on screen.
  ///
  /// False for the whole life of an operation that resolved faster than the
  /// configured [LoadingTiming.delay] — such an operation never paints.
  bool get isVisible => _operation.shown && !_operation.removed;

  /// The current indicator state for this operation.
  LoadingStatus get status => _operation.status;

  /// Completes once the operation has fully left the screen.
  Future<void> get closed => _operation.closed.future;

  /// Sets determinate progress, or null to return to an indeterminate spin.
  set progress(double? value) => _controller.updateOperation(
    _operation,
    progress: value,
    setProgress: true,
  );

  /// Replaces the primary message.
  set message(String? value) =>
      _controller.updateOperation(_operation, message: value, setMessage: true);

  /// Updates any combination of text and progress in one notification.
  ///
  /// Omitted arguments are left untouched. To clear a field rather than leave
  /// it, pass the matching `clear` flag.
  void update({
    String? message,
    String? detail,
    double? progress,
    bool clearMessage = false,
    bool clearDetail = false,
    bool clearProgress = false,
  }) {
    _controller.updateOperation(
      _operation,
      message: message,
      detail: detail,
      progress: progress,
      setMessage: message != null || clearMessage,
      setDetail: detail != null || clearDetail,
      setProgress: progress != null || clearProgress,
    );
  }

  /// Settles into a check mark, holds, then dismisses.
  ///
  /// If the operation never became visible, no check mark is shown — a fast
  /// success stays silent rather than flashing.
  Future<void> success([String? message]) => _controller.retire(
    _operation,
    status: LoadingStatus.success,
    message: message,
  );

  /// Settles into a cross, holds, then dismisses.
  Future<void> error([String? message]) => _controller.retire(
    _operation,
    status: LoadingStatus.error,
    message: message,
  );

  /// Dismisses with no terminal feedback, respecting the minimum-visible rule.
  Future<void> dismiss() => _controller.retire(_operation);

  /// Removes the operation immediately, skipping every timing guarantee.
  ///
  /// Reserved for teardown such as route changes, where a graceful exit would
  /// animate over a screen that no longer exists.
  Future<void> dismissNow() => _controller.retire(_operation, immediate: true);
}
