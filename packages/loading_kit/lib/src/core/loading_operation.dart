import 'dart:async';

import 'loading_status.dart';
import 'loading_timing.dart';

/// One unit of in-flight work tracked by a controller.
///
/// Internal to the package. Callers interact with the `LoadingHandle` that
/// wraps an operation rather than with the operation itself.
///
/// The lifecycle is driven entirely by [Timer]s rather than wall-clock
/// arithmetic, which keeps it deterministic under `WidgetTester.pump` and
/// `fakeAsync` — a controller's timing rules are therefore testable without
/// any real waiting.
class LoadingOperation {
  /// Creates an operation. Called by the controller, not by user code.
  LoadingOperation({
    required this.timing,
    this.message,
    this.detail,
    this.progress,
    this.dismissible = false,
  });

  /// The timing policy applied to this operation specifically.
  final LoadingTiming timing;

  /// Primary text for this operation.
  String? message;

  /// Secondary text for this operation.
  String? detail;

  /// Determinate progress, or null when indeterminate.
  double? progress;

  /// Whether tapping the scrim retires this operation.
  bool dismissible;

  /// Whether a route change should retire this operation automatically.
  ///
  /// True by default, which is what stops an overlay from outliving the
  /// screen that started it.
  bool dismissOnNavigation = true;

  /// The indicator state for this operation.
  LoadingStatus status = LoadingStatus.busy;

  /// Invoked when the user cancels. Null when cancellation is not offered.
  void Function()? onCancel;

  /// Whether the cancel affordance is currently offered.
  bool cancelOffered = false;

  /// Whether this operation has passed its reveal delay and is painted.
  bool shown = false;

  /// Whether the minimum-visible window has elapsed.
  bool minElapsed = false;

  /// Whether retirement was requested before the minimum window elapsed.
  bool retireAfterMin = false;

  /// Whether retirement has begun. Guards against double-retiring.
  bool retiring = false;

  /// Whether the operation has been fully removed from its controller.
  bool removed = false;

  /// Fires at the end of the reveal delay, promoting the operation to shown.
  Timer? revealTimer;

  /// Fires at the end of the minimum-visible window.
  Timer? minTimer;

  /// Fires at the end of a success or error hold.
  Timer? holdTimer;

  /// Fires when the cancel affordance should appear.
  Timer? cancelTimer;

  /// Completes once the operation has fully left the screen.
  final Completer<void> closed = Completer<void>();

  /// Cancels every pending timer for this operation.
  void cancelTimers() {
    revealTimer?.cancel();
    minTimer?.cancel();
    holdTimer?.cancel();
    cancelTimer?.cancel();
    revealTimer = null;
    minTimer = null;
    holdTimer = null;
    cancelTimer = null;
  }
}
