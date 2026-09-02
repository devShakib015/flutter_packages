import 'dart:async';

import 'loading_controller.dart';
import 'loading_exceptions.dart';
import 'loading_handle.dart';
import 'loading_state.dart';
import 'loading_status.dart';
import 'loading_task.dart';
import 'loading_timing.dart';

/// A global entry point that forwards to the controller installed by
/// `LoadingKit.builder`.
///
/// This exists so loading can be triggered from a repository or a bloc that
/// has no [BuildContext]:
///
/// ```dart
/// final user = await Loading.run(() => api.signIn(email, password));
/// ```
///
/// It is a convenience over the real API, not a replacement for it. The
/// controller underneath is an ordinary object; prefer `context.loading` or
/// your own [LoadingController] where a context is available, since a scoped
/// controller is trivially testable and a global one is shared state.
abstract final class Loading {
  /// Hosts in mount order. The innermost one wins while it is mounted, and
  /// unmounting it hands the facade back rather than destroying it.
  ///
  /// A plain field held only the newest host, so a nested [LoadingHost] — a
  /// modal route with its own, say — replaced the root on mount and set the
  /// facade to null on unmount. Every later `Loading.show()` in the app then
  /// threw [LoadingHostMissing] even though the root host was still there.
  static final List<LoadingController> _stack = <LoadingController>[];

  static LoadingController? get _instance =>
      _stack.isEmpty ? null : _stack.last;

  /// Registers [controller] as the global target. Called by the host.
  static void attach(LoadingController controller) {
    _stack
      ..remove(controller)
      ..add(controller);
  }

  /// Unregisters [controller], handing the facade back to the host beneath it.
  static void detach(LoadingController controller) => _stack.remove(controller);

  /// Whether a host is installed.
  static bool get isInstalled => _instance != null;

  /// The controller behind the facade.
  ///
  /// Throws [LoadingHostMissing] when no host is installed.
  static LoadingController get instance {
    final LoadingController? controller = _instance;
    if (controller == null) throw LoadingHostMissing();
    return controller;
  }

  /// Whether any operation is in flight.
  static bool get isBusy => _instance?.isBusy ?? false;

  /// Whether the overlay is currently painted.
  static bool get isVisible => _instance?.isVisible ?? false;

  /// The current snapshot, or [LoadingState.idle] when no host is installed.
  static LoadingState get state => _instance?.value ?? LoadingState.idle;

  /// Starts an operation. See [LoadingController.show].
  static LoadingHandle show({
    String? message,
    String? detail,
    double? progress,
    LoadingTiming? timing,
    bool dismissible = false,
    bool dismissOnNavigation = true,
  }) => instance.show(
    message: message,
    detail: detail,
    progress: progress,
    timing: timing,
    dismissible: dismissible,
    dismissOnNavigation: dismissOnNavigation,
  );

  /// Runs [task] behind the overlay. See [LoadingController.run].
  static Future<T> run<T>(
    FutureOr<T> Function() task, {
    String? message,
    String? detail,
    double? progress,
    String? successMessage,
    String? errorMessage,
    Duration? timeout,
    LoadingTiming? timing,
    bool dismissible = false,
    bool awaitFeedback = true,
  }) => instance.run<T>(
    task,
    message: message,
    detail: detail,
    progress: progress,
    successMessage: successMessage,
    errorMessage: errorMessage,
    timeout: timeout,
    timing: timing,
    dismissible: dismissible,
    awaitFeedback: awaitFeedback,
  );

  /// Runs [body] with progress and cancellation. See
  /// [LoadingController.runTask].
  static Future<T> runTask<T>(
    FutureOr<T> Function(LoadingTask task) body, {
    String? message,
    String? detail,
    double? progress,
    String? successMessage,
    String? errorMessage,
    Duration? timeout,
    Duration? cancelAfter,
    LoadingTiming? timing,
    bool dismissible = false,
    bool awaitFeedback = true,
  }) => instance.runTask<T>(
    body,
    message: message,
    detail: detail,
    progress: progress,
    successMessage: successMessage,
    errorMessage: errorMessage,
    timeout: timeout,
    cancelAfter: cancelAfter,
    timing: timing,
    dismissible: dismissible,
    awaitFeedback: awaitFeedback,
  );

  /// Shows a transient, non-blocking message.
  ///
  /// ```dart
  /// Loading.toast('Draft saved');
  /// ```
  static Object toast(
    String message, {
    String? detail,
    LoadingStatus? status,
    Duration? duration,
  }) => instance.toast(
    message,
    detail: detail,
    status: status,
    duration: duration,
  );

  /// A toast carrying a check mark.
  static Object toastSuccess(
    String message, {
    String? detail,
    Duration? duration,
  }) => instance.toast(
    message,
    detail: detail,
    status: LoadingStatus.success,
    duration: duration,
  );

  /// A toast carrying a cross.
  static Object toastError(
    String message, {
    String? detail,
    Duration? duration,
  }) => instance.toast(
    message,
    detail: detail,
    status: LoadingStatus.error,
    duration: duration,
  );

  /// Starts the exit transition for one toast.
  static void dismissToast(Object id) => _instance?.dismissToast(id);

  /// Removes every toast immediately.
  static void clearToasts() => _instance?.clearToasts();

  /// Retires every operation. See [LoadingController.dismissAll].
  static Future<void> dismissAll({bool immediate = false}) =>
      _instance?.dismissAll(immediate: immediate) ?? Future<void>.value();
}
