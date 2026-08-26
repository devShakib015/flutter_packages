import 'package:flutter/foundation.dart';

import 'loading_status.dart';

/// An immutable snapshot of what the overlay should currently render.
///
/// A [LoadingController] derives exactly one of these from however many
/// operations are in flight, so the overlay only ever listens to a single
/// value and rebuilds a single subtree.
@immutable
class LoadingState {
  /// Creates a snapshot. Prefer reading these from a controller.
  const LoadingState({
    required this.visible,
    this.status = LoadingStatus.busy,
    this.message,
    this.detail,
    this.progress,
    this.cancellable = false,
    this.dismissible = false,
    this.depth = 0,
  });

  /// Nothing is on screen and nothing is pending.
  static const LoadingState idle = LoadingState(visible: false);

  /// Whether the overlay should be painted.
  ///
  /// False while an operation is still inside its reveal delay, which is what
  /// makes fast operations render nothing at all.
  final bool visible;

  /// Whether the indicator is spinning, or has settled into a check or cross.
  final LoadingStatus status;

  /// The primary line of text, such as `'Signing in…'`.
  final String? message;

  /// A secondary, quieter line beneath [message].
  final String? detail;

  /// Determinate progress from 0.0 to 1.0, or null when indeterminate.
  final double? progress;

  /// Whether a cancel affordance should be offered.
  final bool cancellable;

  /// Whether tapping the scrim dismisses the operation.
  final bool dismissible;

  /// How many operations are currently painted.
  ///
  /// Reference counting means two overlapping calls raise this to 2, and the
  /// overlay only leaves once both have retired.
  final int depth;

  /// Whether determinate progress is being reported.
  bool get isDeterminate => progress != null;

  /// Whether any text will be rendered alongside the indicator.
  bool get hasText => message != null || detail != null;

  /// Returns a copy with the given fields replaced.
  LoadingState copyWith({
    bool? visible,
    LoadingStatus? status,
    String? message,
    String? detail,
    double? progress,
    bool? cancellable,
    bool? dismissible,
    int? depth,
  }) {
    return LoadingState(
      visible: visible ?? this.visible,
      status: status ?? this.status,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      progress: progress ?? this.progress,
      cancellable: cancellable ?? this.cancellable,
      dismissible: dismissible ?? this.dismissible,
      depth: depth ?? this.depth,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingState &&
          other.visible == visible &&
          other.status == status &&
          other.message == message &&
          other.detail == detail &&
          other.progress == progress &&
          other.cancellable == cancellable &&
          other.dismissible == dismissible &&
          other.depth == depth;

  @override
  int get hashCode => Object.hash(
    visible,
    status,
    message,
    detail,
    progress,
    cancellable,
    dismissible,
    depth,
  );

  @override
  String toString() => visible
      ? 'LoadingState(${status.name}, message: $message, '
            'progress: $progress, depth: $depth)'
      : 'LoadingState.idle';
}
