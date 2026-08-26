import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/loading_status.dart';
import '../theme/loading_indicator_style.dart';

/// Sub-cycles per rotation, matching the cadence of Material's own spinner.
const int _kPathCount = 5;

/// Where a determinate arc begins: twelve o'clock.
const double _kStartAngle = -math.pi / 2;

/// Smallest sweep drawn, so the arc never collapses to nothing.
const double _kMinSweep = 0.05;

final Animatable<double> _kHeadTween = CurveTween(
  curve: const Interval(0.0, 0.5, curve: Curves.fastOutSlowIn),
).chain(CurveTween(curve: const SawTooth(_kPathCount)));

final Animatable<double> _kTailTween = CurveTween(
  curve: const Interval(0.5, 1.0, curve: Curves.fastOutSlowIn),
).chain(CurveTween(curve: const SawTooth(_kPathCount)));

final Animatable<double> _kRotationTween = CurveTween(
  curve: const SawTooth(_kPathCount),
);

final Animatable<int> _kStepTween = StepTween(begin: 0, end: _kPathCount);

/// Draws every indicator form, and the success and error glyphs they settle
/// into.
///
/// The painter snapshots its animation values, so a fresh instance is built
/// per frame by an [AnimatedBuilder]. It deliberately does **not** accept a
/// `repaint` listenable: that re-runs [paint] against stale fields, which
/// renders a completely motionless indicator while every test still passes.
///
/// [LoadingIndicatorStyle.arc] is special-cased. Its busy and terminal forms
/// are one continuous shape — the arc closes into a ring and the glyph strokes
/// on inside it. Every other style cross-fades into that ring instead, so the
/// outcome always looks the same no matter which spinner precedes it.
class LoadingIndicatorPainter extends CustomPainter {
  /// Creates the painter. Driven by `LoadingIndicator`.
  LoadingIndicatorPainter({
    required this.style,
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
  });

  /// Which indeterminate form to draw.
  final LoadingIndicatorStyle style;

  /// The busy cycle position, 0.0 to 1.0, wrapping continuously.
  final double spin;

  /// How far the indicator has settled into its terminal state, 0.0 to 1.0.
  final double morph;

  /// Which terminal glyph the morph is heading toward.
  final LoadingStatus status;

  /// Determinate progress from 0.0 to 1.0, or null to animate indeterminately.
  final double? progress;

  /// Colour of the form while busy.
  final Color color;

  /// Colour of the unfilled track. Skipped when fully transparent.
  final Color trackColor;

  /// Colour on success.
  final Color successColor;

  /// Colour on error.
  final Color errorColor;

  /// Stroke width of arcs and glyphs, and the scale reference for solid forms.
  final double strokeWidth;

  /// Blur radius of a glow beneath the form. Zero skips the glow pass.
  final double glow;

  Color get _terminalColor =>
      status == LoadingStatus.error ? errorColor : successColor;

  static Color _fade(Color color, double opacity) =>
      color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));

  Paint _strokePaint(Color color, [double? width]) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = width ?? strokeWidth
    ..color = color;

  Paint _fillPaint(Color color) => Paint()
    ..style = PaintingStyle.fill
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;
    final Offset center = Offset(size.width / 2, size.height / 2);

    // Determinate work is always an arc: it is the only busy form that reads
    // as a proportion. A pulsing dot cannot say "62%".
    if (style == LoadingIndicatorStyle.arc || progress != null) {
      _paintArcForm(canvas, size, center, radius);
      return;
    }

    final double settle = Curves.easeOut.transform(
      (morph / 0.30).clamp(0.0, 1.0),
    );
    if (settle < 1.0) {
      _paintBusyForm(canvas, center, radius, 1.0 - settle);
    }
    if (settle > 0.0) {
      final double glyph = Curves.easeOutCubic.transform(
        ((morph - 0.25) / 0.75).clamp(0.0, 1.0),
      );
      _paintTerminal(canvas, size, center, radius, settle, glyph);
    }
  }

  // ---------------------------------------------------------------- arc form

  void _paintArcForm(Canvas canvas, Size size, Offset center, double radius) {
    final Rect circle = Rect.fromCircle(center: center, radius: radius);

    final double closing = Curves.easeOutCubic.transform(
      (morph / 0.45).clamp(0.0, 1.0),
    );
    final double glyphPhase = Curves.easeOutCubic.transform(
      ((morph - 0.38) / 0.62).clamp(0.0, 1.0),
    );

    final Color active = morph == 0
        ? color
        : Color.lerp(color, _terminalColor, Curves.easeOut.transform(closing))!;

    if (trackColor.a > 0) {
      canvas.drawCircle(center, radius, _strokePaint(trackColor));
    }

    final (double start, double sweep) = _arcGeometry(closing);

    if (glow > 0) {
      canvas.drawArc(
        circle,
        start,
        sweep,
        false,
        _strokePaint(_fade(active, 0.55))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
      );
    }
    canvas.drawArc(circle, start, sweep, false, _strokePaint(active));

    if (glyphPhase > 0) {
      _paintGlyph(canvas, size, center, glyphPhase, active);
    }
  }

  (double, double) _arcGeometry(double closing) {
    if (morph > 0) {
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

    return (
      _kStartAngle +
          tail * 3 / 2 * math.pi +
          rotation * 2 * math.pi +
          step * 0.5 * math.pi,
      math.max((head - tail) * 3 / 2 * math.pi, _kMinSweep),
    );
  }

  // -------------------------------------------------------------- busy forms

  void _paintBusyForm(
    Canvas canvas,
    Offset center,
    double radius,
    double opacity,
  ) {
    switch (style) {
      case LoadingIndicatorStyle.arc:
        break;
      case LoadingIndicatorStyle.dots:
        _paintDots(canvas, center, radius, opacity);
      case LoadingIndicatorStyle.bars:
        _paintBars(canvas, center, radius, opacity);
      case LoadingIndicatorStyle.orbit:
        _paintOrbit(canvas, center, radius, opacity);
      case LoadingIndicatorStyle.pulse:
        _paintPulse(canvas, center, radius, opacity);
      case LoadingIndicatorStyle.ripple:
        _paintRipple(canvas, center, radius, opacity);
    }
  }

  void _paintDots(Canvas canvas, Offset center, double radius, double o) {
    const int count = 3;
    final double dot = radius * 0.28;
    final double gap = radius * 0.80;
    for (var i = 0; i < count; i++) {
      final double wave = _wave(i / count);
      canvas.drawCircle(
        Offset(center.dx + (i - 1) * gap, center.dy),
        dot * (0.45 + 0.55 * wave),
        _fillPaint(_fade(color, o * (0.35 + 0.65 * wave))),
      );
    }
  }

  void _paintBars(Canvas canvas, Offset center, double radius, double o) {
    const int count = 4;
    final double width = radius * 0.30;
    final double gap = radius * 0.18;
    final double total = count * width + (count - 1) * gap;
    final Paint paint = _fillPaint(_fade(color, o));
    for (var i = 0; i < count; i++) {
      final double height = radius * 2 * (0.28 + 0.72 * _wave(i / count));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center.dx - total / 2 + i * (width + gap),
            center.dy - height / 2,
            width,
            height,
          ),
          Radius.circular(width / 2),
        ),
        paint,
      );
    }
  }

  void _paintOrbit(Canvas canvas, Offset center, double radius, double o) {
    if (trackColor.a > 0) {
      canvas.drawCircle(center, radius, _strokePaint(_fade(trackColor, o)));
    }
    final double angle = spin * 2 * math.pi + _kStartAngle;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle - 1.0,
      1.0,
      false,
      _strokePaint(_fade(color, o * 0.42)),
    );
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius,
      strokeWidth * 0.95,
      _fillPaint(_fade(color, o)),
    );
  }

  void _paintPulse(Canvas canvas, Offset center, double radius, double o) {
    for (final double offset in const <double>[0.0, 0.5]) {
      final double t = (spin + offset) % 1.0;
      canvas.drawCircle(
        center,
        radius * (0.26 + 0.74 * t),
        _fillPaint(_fade(color, o * (1.0 - t) * 0.8)),
      );
    }
  }

  void _paintRipple(Canvas canvas, Offset center, double radius, double o) {
    for (final double offset in const <double>[0.0, 0.5]) {
      final double t = (spin + offset) % 1.0;
      if (t < 0.02) continue;
      canvas.drawCircle(
        center,
        radius * t,
        _strokePaint(_fade(color, o * (1.0 - t))),
      );
    }
  }

  /// A 0..1 sine wave offset into the cycle, for staggered forms.
  double _wave(double offset) =>
      0.5 + 0.5 * math.sin(((spin + offset) % 1.0) * 2 * math.pi);

  // ---------------------------------------------------------------- terminal

  void _paintTerminal(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double opacity,
    double glyph,
  ) {
    final Color tint = _fade(_terminalColor, opacity);
    final double scale = 0.84 + 0.16 * Curves.easeOutBack.transform(opacity);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);

    if (glow > 0) {
      canvas.drawCircle(
        center,
        radius,
        _strokePaint(_fade(tint, 0.55))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
      );
    }
    canvas.drawCircle(center, radius, _strokePaint(tint));
    if (glyph > 0) _paintGlyph(canvas, size, center, glyph, tint);
    canvas.restore();
  }

  void _paintGlyph(
    Canvas canvas,
    Size size,
    Offset center,
    double phase,
    Color color,
  ) {
    final Path path = status == LoadingStatus.error
        ? _buildCross(size)
        : _buildCheck(size);
    final Paint paint = _strokePaint(color);
    final double scale = 0.92 + 0.08 * Curves.easeOutBack.transform(phase);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.translate(-center.dx, -center.dy);
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

  static Path _buildCheck(Size size) => Path()
    ..moveTo(size.width * 0.28, size.height * 0.52)
    ..lineTo(size.width * 0.44, size.height * 0.68)
    ..lineTo(size.width * 0.73, size.height * 0.35);

  static Path _buildCross(Size size) => Path()
    ..moveTo(size.width * 0.35, size.height * 0.35)
    ..lineTo(size.width * 0.65, size.height * 0.65)
    ..moveTo(size.width * 0.65, size.height * 0.35)
    ..lineTo(size.width * 0.35, size.height * 0.65);

  @override
  bool shouldRepaint(LoadingIndicatorPainter old) =>
      old.style != style ||
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
