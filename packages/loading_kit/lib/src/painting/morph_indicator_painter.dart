import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/loading_status.dart';

/// Number of sub-cycles inside one rotation period, matching the cadence of
/// Material's own indeterminate indicator.
const int _kPathCount = 5;

/// Angle the arc starts from when reporting determinate progress.
const double _kStartAngle = -math.pi / 2;

/// Smallest sweep drawn, so the arc never collapses to nothing.
const double _kMinSweep = 0.05;

final Animatable<double> _kHeadTween = CurveTween(
  curve: const Interval(0.0, 0.5, curve: Curves.fastOutSlowIn),
).chain(CurveTween(curve: const SawTooth(_kPathCount)));

final Animatable<double> _kTailTween = CurveTween(
  curve: const Interval(0.5, 1.0, curve: Curves.fastOutSlowIn),
).chain(CurveTween(curve: const SawTooth(_kPathCount)));

final Animatable<double> _kRotationTween =
    CurveTween(curve: const SawTooth(_kPathCount));

final Animatable<int> _kStepTween = StepTween(begin: 0, end: _kPathCount);

/// Paints the spinner, the determinate arc, and the success and error glyphs
/// as one continuous form.
///
/// The whole indicator is a single painter on purpose. Swapping a spinner
/// widget for a check-mark widget is what makes most loading packages feel
/// disjointed: the arc vanishes and an unrelated icon pops in. Here the arc
/// closes into a full circle, its colour crosses to the terminal hue, and the
/// glyph strokes itself on inside that circle — one continuous gesture from a
/// single animation value.
class MorphIndicatorPainter extends CustomPainter {
  /// Creates the painter. Driven by [LoadingIndicator], which owns the
  /// animation controllers.
  MorphIndicatorPainter({
    required this.spin,
    required this.morph,
    required this.status,
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.successColor,
    required this.errorColor,
    required this.strokeWidth,
    required this.glow,
    super.repaint,
  });

  /// The indeterminate cycle position, 0.0 to 1.0, wrapping continuously.
  final double spin;

  /// How far the indicator has settled into its terminal state, 0.0 to 1.0.
  final double morph;

  /// Which terminal glyph the morph is heading toward.
  final LoadingStatus status;

  /// Determinate progress from 0.0 to 1.0, or null to spin indeterminately.
  final double? progress;

  /// Arc colour while busy.
  final Color color;

  /// Colour of the unfilled track. Skipped entirely when fully transparent.
  final Color trackColor;

  /// Arc and glyph colour on success.
  final Color successColor;

  /// Arc and glyph colour on error.
  final Color errorColor;

  /// Stroke width of the arc and glyphs.
  final double strokeWidth;

  /// Blur radius of the glow drawn beneath the arc. Zero skips the glow pass.
  final double glow;

  // Glyph paths depend only on the box, so they survive across frames and are
  // rebuilt only when the indicator is resized.
  static Size? _cachedSize;
  static Path? _cachedCheck;
  static Path? _cachedCross;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);
    final Rect circle = Rect.fromCircle(center: center, radius: radius);

    // The arc closes into a full ring over the first 45% of the morph; the
    // glyph draws itself over the remainder.
    final double closing = Curves.easeOutCubic.transform(
      (morph / 0.45).clamp(0.0, 1.0),
    );
    final double glyphPhase = Curves.easeOutCubic.transform(
      ((morph - 0.38) / 0.62).clamp(0.0, 1.0),
    );

    final Color terminal =
        status == LoadingStatus.error ? errorColor : successColor;
    final Color active = morph == 0
        ? color
        : Color.lerp(color, terminal, Curves.easeOut.transform(closing))!;

    if (trackColor.a > 0) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = trackColor,
      );
    }

    final (double start, double sweep) = _arcGeometry(closing);

    if (glow > 0) {
      canvas.drawArc(
        circle,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth
          ..color = active.withValues(alpha: active.a * 0.55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
      );
    }

    canvas.drawArc(
      circle,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = active,
    );

    if (glyphPhase > 0) {
      _paintGlyph(canvas, size, glyphPhase, active);
    }
  }

  /// Returns the start angle and sweep of the arc for this frame.
  (double, double) _arcGeometry(double closing) {
    if (morph > 0) {
      // Settling: grow whatever was on screen out to a complete ring.
      final double from = progress ?? 0.75;
      final double fraction = from + (1.0 - from) * closing;
      return (_kStartAngle, fraction * math.pi * 2);
    }

    if (progress != null) {
      final double clamped = progress!.clamp(0.0, 1.0);
      return (
        _kStartAngle,
        math.max(clamped * math.pi * 2, clamped > 0 ? _kMinSweep : 0.0),
      );
    }

    final double head = _kHeadTween.transform(spin);
    final double tail = _kTailTween.transform(spin);
    final double rotation = _kRotationTween.transform(spin);
    final double step = _kStepTween.transform(spin).toDouble();

    final double start = _kStartAngle +
        tail * 3 / 2 * math.pi +
        rotation * 2 * math.pi +
        step * 0.5 * math.pi;
    final double sweep =
        math.max((head - tail) * 3 / 2 * math.pi, _kMinSweep);
    return (start, sweep);
  }

  void _paintGlyph(Canvas canvas, Size size, double phase, Color color) {
    if (_cachedSize != size || _cachedCheck == null || _cachedCross == null) {
      _cachedSize = size;
      _cachedCheck = _buildCheck(size);
      _cachedCross = _buildCross(size);
    }
    final Path path =
        status == LoadingStatus.error ? _cachedCross! : _cachedCheck!;

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = strokeWidth
      ..color = color;

    // A slight overshoot on the way in gives the glyph a physical snap.
    final double scale = 0.92 + 0.08 * Curves.easeOutBack.transform(phase);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);
    _drawProgressively(canvas, path, phase, paint);
    canvas.restore();
  }

  /// Strokes [path] on from its start to [fraction] of its total length.
  static void _drawProgressively(
    Canvas canvas,
    Path path,
    double fraction,
    Paint paint,
  ) {
    if (fraction >= 1.0) {
      canvas.drawPath(path, paint);
      return;
    }
    final List<ui.PathMetric> metrics = path.computeMetrics().toList();
    final double total = metrics.fold<double>(
      0,
      (double sum, ui.PathMetric m) => sum + m.length,
    );
    var remaining = total * fraction;
    for (final ui.PathMetric metric in metrics) {
      if (remaining <= 0) break;
      final double take = math.min(remaining, metric.length);
      canvas.drawPath(metric.extractPath(0, take), paint);
      remaining -= take;
    }
  }

  static Path _buildCheck(Size size) {
    final double w = size.width;
    final double h = size.height;
    return Path()
      ..moveTo(w * 0.28, h * 0.52)
      ..lineTo(w * 0.44, h * 0.68)
      ..lineTo(w * 0.73, h * 0.35);
  }

  static Path _buildCross(Size size) {
    final double w = size.width;
    final double h = size.height;
    return Path()
      ..moveTo(w * 0.35, h * 0.35)
      ..lineTo(w * 0.65, h * 0.65)
      ..moveTo(w * 0.65, h * 0.35)
      ..lineTo(w * 0.35, h * 0.65);
  }

  @override
  bool shouldRepaint(MorphIndicatorPainter old) =>
      old.spin != spin ||
      old.morph != morph ||
      old.status != status ||
      old.progress != progress ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.successColor != successColor ||
      old.errorColor != errorColor ||
      old.strokeWidth != strokeWidth ||
      old.glow != glow;
}
