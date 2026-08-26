import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/loading_status.dart';

/// One sweep of the indeterminate bar.
const Duration _kSweepPeriod = Duration(milliseconds: 1400);

/// How long the bar takes to catch up to a new progress value.
const Duration _kFillDuration = Duration(milliseconds: 340);

/// A horizontal progress bar, determinate or indeterminate.
///
/// Used by the overlay when the resolved style asks for
/// `LoadingProgressStyle.bar`, and usable on its own anywhere.
///
/// For long operations a bar is easier to read at a glance than an arc — the
/// difference between 60% and 70% is obvious in a line and subtle in a circle.
class LoadingProgressBar extends StatefulWidget {
  /// Creates a progress bar.
  const LoadingProgressBar({
    super.key,
    this.progress,
    this.status = LoadingStatus.busy,
    required this.color,
    required this.trackColor,
    this.successColor,
    this.errorColor,
    this.width = 200,
    this.thickness = 6,
  });

  /// Determinate progress from 0.0 to 1.0, or null to sweep indeterminately.
  final double? progress;

  /// Whether work is in progress, or has settled.
  final LoadingStatus status;

  /// Fill colour while busy.
  final Color color;

  /// Colour of the unfilled track.
  final Color trackColor;

  /// Fill colour on success. Defaults to [color].
  final Color? successColor;

  /// Fill colour on error. Defaults to [color].
  final Color? errorColor;

  /// Width of the bar.
  final double width;

  /// Height of the bar.
  final double thickness;

  @override
  State<LoadingProgressBar> createState() => _LoadingProgressBarState();
}

class _LoadingProgressBarState extends State<LoadingProgressBar>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: _kSweepPeriod,
  );
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: _kFillDuration,
  );
  Animation<double>? _fillAnimation;
  late final Listenable _repaint = Listenable.merge(<Listenable>[
    _sweep,
    _fill,
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.progress == null && !widget.status.isTerminal) _sweep.repeat();
    if (widget.progress != null) {
      _fillAnimation = AlwaysStoppedAnimation<double>(widget.progress!);
    }
  }

  @override
  void didUpdateWidget(LoadingProgressBar old) {
    super.didUpdateWidget(old);
    final bool shouldSweep =
        widget.progress == null && !widget.status.isTerminal;
    if (shouldSweep && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!shouldSweep && _sweep.isAnimating) {
      _sweep.stop();
    }
    if (widget.progress != old.progress || widget.status != old.status) {
      // Settling fills the bar the rest of the way rather than leaving it
      // stranded mid-track.
      final double? target = widget.status.isTerminal ? 1.0 : widget.progress;
      if (target != null) {
        final double begin = _fillAnimation?.value ?? old.progress ?? target;
        _fillAnimation = Tween<double>(
          begin: begin,
          end: target,
        ).animate(CurvedAnimation(parent: _fill, curve: Curves.easeOutCubic));
        _fill.forward(from: 0);
      } else {
        _fillAnimation = null;
      }
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _fill.dispose();
    super.dispose();
  }

  Color get _activeColor => switch (widget.status) {
    LoadingStatus.busy => widget.color,
    LoadingStatus.success => widget.successColor ?? widget.color,
    LoadingStatus.error => widget.errorColor ?? widget.color,
  };

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.thickness,
        child: AnimatedBuilder(
          animation: _repaint,
          builder: (BuildContext context, Widget? _) => CustomPaint(
            painter: _BarPainter(
              value: _fillAnimation?.value,
              sweep: _sweep.value,
              color: _activeColor,
              trackColor: widget.trackColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.value,
    required this.sweep,
    required this.color,
    required this.trackColor,
  });

  final double? value;
  final double sweep;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Radius radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = trackColor,
    );

    final Paint fill = Paint()..color = color;

    if (value != null) {
      final double width = size.width * value!.clamp(0.0, 1.0);
      if (width <= 0) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, math.max(width, size.height), size.height),
          radius,
        ),
        fill,
      );
      return;
    }

    // Indeterminate: a segment that accelerates across and off the end.
    const double segment = 0.38;
    final double head = Curves.easeInOut.transform(sweep) * (1 + segment);
    final double start = ((head - segment) * size.width).clamp(0.0, size.width);
    final double end = (head * size.width).clamp(0.0, size.width);
    if (end - start <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(start, 0, end, size.height),
        radius,
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.value != value ||
      old.sweep != sweep ||
      old.color != color ||
      old.trackColor != trackColor;
}
