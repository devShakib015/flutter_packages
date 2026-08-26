import 'package:flutter/foundation.dart';

/// Timing policy governing when the overlay appears, how long it is guaranteed
/// to remain once it has, and how long terminal feedback lingers.
///
/// The defaults implement the two rules that separate a considered loading
/// overlay from a janky one:
///
/// * **Nothing paints before [delay].** An operation that resolves in 90ms
///   never shows an overlay at all, so fast paths stay visually silent
///   instead of strobing.
/// * **Once painted, it holds for [minVisible].** An overlay that appears at
///   140ms and is torn down at 170ms reads as a glitch. Holding it for half a
///   second reads as a deliberate response to the tap.
///
/// Together these eliminate the "flash of loading indicator" that makes most
/// overlay packages feel cheap on a fast connection.
@immutable
class LoadingTiming {
  /// Creates a timing policy. The defaults are tuned for network-backed UI.
  const LoadingTiming({
    this.delay = const Duration(milliseconds: 140),
    this.minVisible = const Duration(milliseconds: 520),
    this.successHold = const Duration(milliseconds: 900),
    this.errorHold = const Duration(milliseconds: 1800),
    this.enter = const Duration(milliseconds: 240),
    this.exit = const Duration(milliseconds: 180),
  });

  /// How long an operation must run before the overlay is allowed to paint.
  ///
  /// Operations that finish inside this window are never rendered.
  final Duration delay;

  /// The minimum time the overlay stays on screen once it has painted.
  final Duration minVisible;

  /// How long a success state lingers before dismissing.
  final Duration successHold;

  /// How long an error state lingers before dismissing.
  final Duration errorHold;

  /// Duration of the entrance transition.
  final Duration enter;

  /// Duration of the exit transition.
  final Duration exit;

  /// Paints immediately and dismisses immediately.
  ///
  /// Useful for demos, tests, and deliberately synchronous feedback. Prefer
  /// the default policy in production — [instant] reintroduces flicker.
  static const LoadingTiming instant = LoadingTiming(
    delay: Duration.zero,
    minVisible: Duration.zero,
    successHold: Duration(milliseconds: 600),
    errorHold: Duration(milliseconds: 1200),
  );

  /// A patient policy for operations expected to be slow, such as uploads.
  ///
  /// Waits longer before committing to an overlay, then holds longer so the
  /// transition out does not feel abrupt.
  static const LoadingTiming relaxed = LoadingTiming(
    delay: Duration(milliseconds: 260),
    minVisible: Duration(milliseconds: 700),
  );

  /// Returns a copy with the given fields replaced.
  LoadingTiming copyWith({
    Duration? delay,
    Duration? minVisible,
    Duration? successHold,
    Duration? errorHold,
    Duration? enter,
    Duration? exit,
  }) {
    return LoadingTiming(
      delay: delay ?? this.delay,
      minVisible: minVisible ?? this.minVisible,
      successHold: successHold ?? this.successHold,
      errorHold: errorHold ?? this.errorHold,
      enter: enter ?? this.enter,
      exit: exit ?? this.exit,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingTiming &&
          other.delay == delay &&
          other.minVisible == minVisible &&
          other.successHold == successHold &&
          other.errorHold == errorHold &&
          other.enter == enter &&
          other.exit == exit;

  @override
  int get hashCode =>
      Object.hash(delay, minVisible, successHold, errorHold, enter, exit);

  @override
  String toString() => 'LoadingTiming(delay: $delay, minVisible: $minVisible)';
}
