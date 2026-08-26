import 'package:flutter/widgets.dart';

import '../core/loading_status.dart';

/// Everything a custom indicator needs to render itself in the current state.
///
/// Handed to a [LoadingIndicatorBuilder] so the replacement can honour the
/// resolved theme rather than hard-coding its own colours and size.
@immutable
class LoadingIndicatorSpec {
  /// Creates a spec. Built by the package, not by user code.
  const LoadingIndicatorSpec({
    required this.status,
    required this.progress,
    required this.size,
    required this.color,
    required this.trackColor,
    required this.successColor,
    required this.errorColor,
    required this.strokeWidth,
  });

  /// Whether work is in progress, or has succeeded or failed.
  final LoadingStatus status;

  /// Determinate progress from 0.0 to 1.0, or null when indeterminate.
  final double? progress;

  /// The diameter the indicator is expected to occupy.
  final double size;

  /// The resolved busy colour.
  final Color color;

  /// The resolved track colour.
  final Color trackColor;

  /// The resolved success colour.
  final Color successColor;

  /// The resolved error colour.
  final Color errorColor;

  /// The resolved stroke width.
  final double strokeWidth;

  /// The colour matching the current [status].
  Color get statusColor => switch (status) {
    LoadingStatus.busy => color,
    LoadingStatus.success => successColor,
    LoadingStatus.error => errorColor,
  };
}

/// Replaces the built-in indicator with a widget of your own.
///
/// This is the escape hatch that makes the package's own shapes optional. Drop
/// in a Lottie animation, a Rive file, your brand mark, or any widget from
/// another spinner package:
///
/// ```dart
/// LoadingKit.builder(
///   style: LoadingStyle.material.copyWith(
///     indicatorBuilder: (context, spec) => SpinKitCubeGrid(
///       color: spec.statusColor,
///       size: spec.size,
///     ),
///   ),
/// )
/// ```
///
/// The builder owns the whole indicator slot, including terminal states, so
/// handle [LoadingIndicatorSpec.status] if you want success and error feedback.
typedef LoadingIndicatorBuilder = Widget Function(
  BuildContext context,
  LoadingIndicatorSpec spec,
);
