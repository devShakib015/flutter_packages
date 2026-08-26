import 'package:flutter/foundation.dart';

import 'loading_status.dart';

/// A transient, non-blocking message.
///
/// Toasts are the counterpart to the blocking overlay: they report that
/// something already happened rather than that something is happening, so they
/// never take a scrim, never swallow input, and dismiss themselves.
@immutable
class LoadingToast {
  /// Creates a toast. Produced by `LoadingController.toast`.
  const LoadingToast({
    required this.id,
    required this.message,
    this.detail,
    this.status,
    this.dismissing = false,
  });

  /// Identity, so the layer can keep widget state across list changes.
  final Object id;

  /// The primary line of text.
  final String message;

  /// A quieter second line.
  final String? detail;

  /// Draws a matching glyph when set. Null shows text alone.
  final LoadingStatus? status;

  /// Whether this toast is playing its exit transition.
  ///
  /// It stays in the list while true so the exit can animate; the controller
  /// removes it once the transition has had time to finish.
  final bool dismissing;

  /// Returns a copy with [dismissing] replaced.
  LoadingToast copyWith({bool? dismissing}) => LoadingToast(
    id: id,
    message: message,
    detail: detail,
    status: status,
    dismissing: dismissing ?? this.dismissing,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingToast &&
          other.id == id &&
          other.message == message &&
          other.detail == detail &&
          other.status == status &&
          other.dismissing == dismissing;

  @override
  int get hashCode => Object.hash(id, message, detail, status, dismissing);

  @override
  String toString() => 'LoadingToast($message, ${status?.name ?? 'plain'})';
}
