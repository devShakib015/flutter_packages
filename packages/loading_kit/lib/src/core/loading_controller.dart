import 'dart:async';

import 'package:flutter/foundation.dart';

import 'loading_exceptions.dart';
import 'loading_handle.dart';
import 'loading_operation.dart';
import 'loading_state.dart';
import 'loading_status.dart';
import 'loading_task.dart';
import 'loading_timing.dart';
import 'loading_toast.dart';

/// Owns every in-flight blocking operation and derives the single
/// [LoadingState] the overlay renders.
///
/// A controller is a [ValueListenable], so the overlay subscribes to exactly
/// one value and rebuilds one small subtree. The rest of the app is never
/// rebuilt when loading starts or stops.
///
/// Most apps never touch a controller directly — `LoadingKit.builder` creates
/// a root one and the global `Loading` facade forwards to it. Create your own
/// when you want a scoped, independently testable overlay:
///
/// ```dart
/// final controller = LoadingController(timing: LoadingTiming.instant);
/// addTearDown(controller.dispose);
/// ```
///
/// ## Reference counting
///
/// Operations stack. Two concurrent [show] calls produce two operations and
/// the overlay stays up until both retire, so an early `hide` from one request
/// cannot strand another mid-flight.
class LoadingController extends ValueNotifier<LoadingState> {
  /// Creates a controller with a default [timing] policy for its operations.
  LoadingController({
    this.timing = const LoadingTiming(),
    this.toastExitDuration = const Duration(milliseconds: 220),
    this.defaultToastDuration = const Duration(seconds: 3),
    this.maxVisibleToasts = 3,
  }) : super(LoadingState.idle);

  /// The timing policy applied to operations that do not override it.
  final LoadingTiming timing;

  /// How long a toast takes to animate out once dismissed.
  ///
  /// The toast stays in the list for this long so its exit can play; keep it
  /// in step with `LoadingToastStyle.enterDuration`.
  final Duration toastExitDuration;

  /// How long a toast stays on screen when [toast] is called without one.
  final Duration defaultToastDuration;

  /// The most toasts shown at once. Older ones are retired to make room.
  final int maxVisibleToasts;

  final List<LoadingOperation> _operations = <LoadingOperation>[];
  final ValueNotifier<List<LoadingToast>> _toasts =
      ValueNotifier<List<LoadingToast>>(const <LoadingToast>[]);
  final Map<Object, Timer> _toastTimers = <Object, Timer>{};
  int _toastSequence = 0;
  bool _disposed = false;

  /// The transient messages currently on screen.
  ValueListenable<List<LoadingToast>> get toasts => _toasts;

  /// Whether any operation is tracked, painted or still inside its delay.
  bool get isBusy => _operations.isNotEmpty;

  /// How many operations are tracked, including ones not yet painted.
  int get activeCount => _operations.length;

  /// Whether the overlay is currently painted.
  bool get isVisible => value.visible;

  /// Whether this controller has been disposed.
  bool get isDisposed => _disposed;

  /// Starts an operation and returns a handle for driving it.
  ///
  /// Nothing paints until [LoadingTiming.delay] elapses, so an operation
  /// retired before then renders nothing at all.
  LoadingHandle show({
    String? message,
    String? detail,
    double? progress,
    LoadingTiming? timing,
    bool dismissible = false,
    bool dismissOnNavigation = true,
  }) {
    assert(!_disposed, 'LoadingController.show() called after dispose().');
    final LoadingTiming effective = timing ?? this.timing;
    final LoadingOperation operation = LoadingOperation(
      timing: effective,
      message: message,
      detail: detail,
      progress: progress,
      dismissible: dismissible,
    )..dismissOnNavigation = dismissOnNavigation;

    _operations.add(operation);

    if (effective.delay <= Duration.zero) {
      _markShown(operation);
    } else {
      operation.revealTimer = Timer(
        effective.delay,
        () => _markShown(operation),
      );
    }
    return LoadingHandle(this, operation);
  }

  /// Runs [task] behind the overlay and returns its result.
  ///
  /// This is the API most callers want. It shows, awaits, and retires in one
  /// statement, and it rethrows whatever [task] threw:
  ///
  /// ```dart
  /// final user = await controller.run(
  ///   () => api.signIn(email, password),
  ///   message: 'Signing in…',
  ///   successMessage: 'Welcome back',
  /// );
  /// ```
  ///
  /// The returned future does not complete until the overlay has finished
  /// leaving. That is deliberate: returning early would let the caller
  /// navigate out from under a still-animating overlay, which is exactly the
  /// flicker this package exists to prevent. Pass `awaitFeedback: false` to
  /// opt out.
  Future<T> run<T>(
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
  }) {
    return runTask<T>(
      (_) => task(),
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
  }

  /// Runs [body], handing it a [LoadingTask] for progress and cancellation.
  ///
  /// Use this instead of [run] when the work reports progress or should be
  /// interruptible. Passing [cancelAfter] reveals a cancel affordance once
  /// that much time has passed, so quick operations never offer one.
  Future<T> runTask<T>(
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
  }) async {
    final LoadingHandle handle = show(
      message: message,
      detail: detail,
      progress: progress,
      timing: timing,
      dismissible: dismissible,
    );
    final LoadingOperation operation = handle.operation;
    final LoadingTask task = LoadingTask(handle);

    final bool interruptible = cancelAfter != null || dismissible;
    if (interruptible) {
      void offer() {
        if (operation.removed) return;
        operation.onCancel = task.markCancelled;
        operation.cancelOffered = cancelAfter != null;
        _publish();
      }

      if (cancelAfter == null || cancelAfter <= Duration.zero) {
        offer();
      } else {
        operation.cancelTimer = Timer(cancelAfter, offer);
      }
    }

    Future<void> settle(Future<void> pending) async {
      if (awaitFeedback) {
        await pending;
      } else {
        unawaited(pending);
      }
    }

    try {
      final Future<T> raw = Future<T>.sync(() => body(task));
      Future<T> guarded = timeout == null ? raw : raw.timeout(timeout);
      if (interruptible) {
        // Future.any attaches an error handler to every branch, so a late
        // failure from the losing branch is absorbed rather than surfacing
        // as an unhandled async error.
        guarded = Future.any<T>(<Future<T>>[
          guarded,
          task.onCancelled.then<T>((_) => throw const LoadingCancelled()),
        ]);
      }

      final T result = await guarded;
      if (task.isCancelled) throw const LoadingCancelled();

      await settle(
        successMessage != null
            ? handle.success(successMessage)
            : handle.dismiss(),
      );
      return result;
    } catch (_) {
      await settle(
        errorMessage != null ? handle.error(errorMessage) : handle.dismiss(),
      );
      rethrow;
    }
  }

  /// Applies changes to [operation]. Called through a [LoadingHandle].
  void updateOperation(
    LoadingOperation operation, {
    String? message,
    String? detail,
    double? progress,
    bool setMessage = false,
    bool setDetail = false,
    bool setProgress = false,
  }) {
    if (_disposed || operation.removed) return;
    var changed = false;
    if (setMessage && operation.message != message) {
      operation.message = message;
      changed = true;
    }
    if (setDetail && operation.detail != detail) {
      operation.detail = detail;
      changed = true;
    }
    if (setProgress && operation.progress != progress) {
      operation.progress = progress;
      changed = true;
    }
    if (changed) _publish();
  }

  /// Retires [operation], honouring the timing policy unless [immediate].
  ///
  /// Returns a future that completes once the operation has fully left.
  Future<void> retire(
    LoadingOperation operation, {
    LoadingStatus? status,
    String? message,
    bool immediate = false,
  }) {
    if (operation.removed) return operation.closed.future;

    if (immediate) {
      _remove(operation);
      return operation.closed.future;
    }
    if (operation.retiring) return operation.closed.future;

    operation.retiring = true;
    operation.revealTimer?.cancel();
    operation.revealTimer = null;
    operation.cancelTimer?.cancel();
    operation.cancelTimer = null;

    // The anti-flicker guarantee: an operation that never painted leaves no
    // trace, not even a success tick. A sign-in that resolved from cache
    // should look instantaneous, not like a flashbulb.
    if (!operation.shown) {
      _remove(operation);
      return operation.closed.future;
    }

    if (status != null && status.isTerminal) {
      operation.status = status;
      if (message != null) operation.message = message;
      operation.cancelOffered = false;
      _publish();

      final Duration hold = status == LoadingStatus.success
          ? operation.timing.successHold
          : operation.timing.errorHold;
      if (hold <= Duration.zero) {
        _retireAfterMinimum(operation);
      } else {
        operation.holdTimer = Timer(hold, () => _retireAfterMinimum(operation));
      }
      return operation.closed.future;
    }

    _retireAfterMinimum(operation);
    return operation.closed.future;
  }

  /// Retires every tracked operation.
  ///
  /// Pass [onlyNavigationScoped] to spare operations that opted out of
  /// automatic dismissal on route changes.
  Future<void> dismissAll({
    bool immediate = false,
    bool onlyNavigationScoped = false,
  }) {
    final List<LoadingOperation> targets = _operations
        .where(
          (LoadingOperation o) =>
              !onlyNavigationScoped || o.dismissOnNavigation,
        )
        .toList(growable: false);
    return Future.wait<void>(
      targets.map((LoadingOperation o) => retire(o, immediate: immediate)),
    );
  }

  /// Shows a transient, non-blocking message and returns its id.
  ///
  /// Unlike [show], this neither blocks input nor draws a scrim, and it
  /// dismisses itself after [duration]:
  ///
  /// ```dart
  /// Loading.toast('Draft saved');
  /// Loading.toast('Could not sync', status: LoadingStatus.error);
  /// ```
  Object toast(
    String message, {
    String? detail,
    LoadingStatus? status,
    Duration? duration,
  }) {
    final Object id = ++_toastSequence;
    final List<LoadingToast> next = <LoadingToast>[
      ..._toasts.value,
      LoadingToast(id: id, message: message, detail: detail, status: status),
    ];
    // Retire the oldest rather than letting a burst of toasts fill the screen.
    while (next.where((LoadingToast t) => !t.dismissing).length >
        maxVisibleToasts) {
      final LoadingToast oldest = next.firstWhere(
        (LoadingToast t) => !t.dismissing,
      );
      dismissToast(oldest.id);
      next.removeWhere((LoadingToast t) => t.id == oldest.id);
    }
    _toasts.value = next;
    _toastTimers[id] = Timer(
      duration ?? defaultToastDuration,
      () => dismissToast(id),
    );
    return id;
  }

  /// Starts the exit transition for the toast with [id].
  void dismissToast(Object id) {
    if (_disposed) return;
    _toastTimers.remove(id)?.cancel();
    final int index = _toasts.value.indexWhere((LoadingToast t) => t.id == id);
    if (index < 0 || _toasts.value[index].dismissing) return;

    final List<LoadingToast> next = <LoadingToast>[..._toasts.value];
    next[index] = next[index].copyWith(dismissing: true);
    _toasts.value = next;

    _toastTimers[id] = Timer(toastExitDuration, () {
      _toastTimers.remove(id);
      if (_disposed) return;
      _toasts.value = _toasts.value
          .where((LoadingToast t) => t.id != id)
          .toList(growable: false);
    });
  }

  /// Removes every toast immediately, with no exit transition.
  void clearToasts() {
    for (final Timer timer in _toastTimers.values) {
      timer.cancel();
    }
    _toastTimers.clear();
    _toasts.value = const <LoadingToast>[];
  }

  /// Invokes the cancel callback of the topmost cancellable operation.
  ///
  /// Wired to the cancel button and, when enabled, to the scrim and the
  /// Android back gesture.
  bool cancelTopmost() {
    for (final LoadingOperation operation in _operations.reversed) {
      final void Function()? onCancel = operation.onCancel;
      if (onCancel != null) {
        onCancel();
        return true;
      }
    }
    return false;
  }

  void _markShown(LoadingOperation operation) {
    if (_disposed || operation.removed) return;
    operation.revealTimer = null;
    operation.shown = true;

    final Duration minimum = operation.timing.minVisible;
    if (minimum <= Duration.zero) {
      operation.minElapsed = true;
    } else {
      operation.minTimer = Timer(minimum, () {
        operation.minElapsed = true;
        if (operation.retireAfterMin) _remove(operation);
      });
    }
    _publish();
  }

  void _retireAfterMinimum(LoadingOperation operation) {
    if (operation.minElapsed) {
      _remove(operation);
    } else {
      operation.retireAfterMin = true;
    }
  }

  void _remove(LoadingOperation operation) {
    if (operation.removed) return;
    operation.removed = true;
    operation.cancelTimers();
    _operations.remove(operation);
    if (!operation.closed.isCompleted) operation.closed.complete();
    _publish();
  }

  void _publish() {
    if (_disposed) return;

    LoadingOperation? busy;
    LoadingOperation? last;
    var visibleCount = 0;

    for (final LoadingOperation operation in _operations) {
      if (!operation.shown) continue;
      visibleCount++;
      last = operation;
      if (!operation.status.isTerminal) busy = operation;
    }

    // A still-running operation outranks one that already settled, so a
    // second request in flight keeps the spinner instead of flashing the
    // first one's check mark.
    final LoadingOperation? top = busy ?? last;
    if (top == null) {
      value = LoadingState.idle;
      return;
    }

    value = LoadingState(
      visible: true,
      status: top.status,
      message: top.message,
      detail: top.detail,
      progress: top.progress,
      cancellable: top.cancelOffered,
      dismissible: top.dismissible,
      depth: visibleCount,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final LoadingOperation operation in List<LoadingOperation>.of(
      _operations,
    )) {
      operation.cancelTimers();
      operation.removed = true;
      if (!operation.closed.isCompleted) operation.closed.complete();
    }
    _operations.clear();
    for (final Timer timer in _toastTimers.values) {
      timer.cancel();
    }
    _toastTimers.clear();
    _toasts.dispose();
    super.dispose();
  }
}
