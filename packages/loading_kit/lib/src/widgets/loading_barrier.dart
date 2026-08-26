import 'package:flutter/material.dart';

import '../core/loading_controller.dart';
import '../core/loading_handle.dart';
import '../core/loading_timing.dart';
import '../theme/loading_style.dart';
import 'loading_overlay.dart';

/// Covers one subtree rather than the whole screen.
///
/// The full-screen host is the wrong shape for a form that saves in place, a
/// card that refreshes, or a button that submits — blacking out the entire app
/// for a local operation is heavy-handed.
///
/// Unlike a hand-rolled `Stack` and a bool, this still honours the timing
/// policy, so a fast save flashes nothing:
///
/// ```dart
/// LoadingBarrier(
///   loading: _saving,
///   message: 'Saving…',
///   borderRadius: BorderRadius.circular(16),
///   child: const ProfileForm(),
/// )
/// ```
///
/// The barrier is sized by its [child] and blocks input only within those
/// bounds. For controller-driven scoped overlays, use `LoadingHost` with
/// `registerGlobal: false` instead.
class LoadingBarrier extends StatefulWidget {
  /// Wraps [child] with a scoped overlay shown while [loading].
  const LoadingBarrier({
    super.key,
    required this.loading,
    required this.child,
    this.message,
    this.detail,
    this.progress,
    this.style = LoadingStyle.adaptive,
    this.timing = const LoadingTiming(),
    this.borderRadius,
  });

  /// Whether the subtree is currently blocked.
  final bool loading;

  /// The subtree being covered.
  final Widget child;

  /// Primary text shown while blocked.
  final String? message;

  /// Secondary text shown while blocked.
  final String? detail;

  /// Determinate progress from 0.0 to 1.0, or null for indeterminate.
  final double? progress;

  /// Appearance of the scoped overlay.
  final LoadingStyle style;

  /// Timing policy. The reveal delay applies here too, so quick work is
  /// invisible.
  final LoadingTiming timing;

  /// Clips the scrim to a rounded rectangle, matching the child's own shape.
  final BorderRadius? borderRadius;

  @override
  State<LoadingBarrier> createState() => _LoadingBarrierState();
}

class _LoadingBarrierState extends State<LoadingBarrier> {
  late final LoadingController _controller = LoadingController(
    timing: widget.timing,
  );
  LoadingHandle? _handle;

  @override
  void initState() {
    super.initState();
    if (widget.loading) _start();
  }

  @override
  void didUpdateWidget(LoadingBarrier old) {
    super.didUpdateWidget(old);
    if (widget.loading && !old.loading) {
      _start();
    } else if (!widget.loading && old.loading) {
      _handle?.dismiss();
      _handle = null;
    } else if (widget.loading) {
      _handle?.update(
        message: widget.message,
        detail: widget.detail,
        progress: widget.progress,
      );
    }
  }

  void _start() {
    _handle = _controller.show(
      message: widget.message,
      detail: widget.detail,
      progress: widget.progress,
      dismissOnNavigation: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget stack = Stack(
      alignment: Alignment.topLeft,
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: LoadingOverlay(controller: _controller, style: widget.style),
        ),
      ],
    );
    if (widget.borderRadius == null) return stack;
    return ClipRRect(borderRadius: widget.borderRadius!, child: stack);
  }
}
