import 'package:flutter/material.dart';

import '../core/loading_status.dart';
import '../painting/morph_indicator_painter.dart';
import '../theme/loading_style.dart';
import '../theme/resolved_loading_style.dart';

/// One rotation cycle of the indeterminate spinner.
const Duration _kSpinPeriod = Duration(milliseconds: 1333);

/// How long the spinner takes to settle into a check or cross.
const Duration _kMorphDuration = Duration(milliseconds: 620);

/// How long a change in determinate progress takes to catch up.
const Duration _kProgressDuration = Duration(milliseconds: 340);

/// The spinner, progress arc, and success and error glyphs, as one widget.
///
/// Usable on its own, anywhere — it does not need an overlay or a controller:
///
/// ```dart
/// const LoadingIndicator(size: 48)
/// LoadingIndicator(progress: 0.6, status: LoadingStatus.busy)
/// ```
///
/// Changing [status] to a terminal value animates the arc closed and strokes
/// the glyph on rather than swapping in a different widget.
class LoadingIndicator extends StatefulWidget {
  /// Creates an indicator. Unset visual arguments fall back to [style].
  const LoadingIndicator({
    super.key,
    this.status = LoadingStatus.busy,
    this.progress,
    this.size,
    this.strokeWidth,
    this.color,
    this.trackColor,
    this.successColor,
    this.errorColor,
    this.glow,
    this.style,
  });

  /// Whether the indicator spins, or has settled into a check or a cross.
  final LoadingStatus status;

  /// Determinate progress from 0.0 to 1.0, or null to spin indeterminately.
  ///
  /// Changes are animated, so reporting progress in coarse jumps still reads
  /// as continuous motion.
  final double? progress;

  /// Diameter in logical pixels.
  final double? size;

  /// Stroke width of the arc and glyphs.
  final double? strokeWidth;

  /// Arc colour while busy.
  final Color? color;

  /// Colour of the unfilled track behind the arc.
  final Color? trackColor;

  /// Arc and glyph colour on success.
  final Color? successColor;

  /// Arc and glyph colour on error.
  final Color? errorColor;

  /// Blur radius of a glow beneath the arc.
  final double? glow;

  /// Supplies any visual token not passed explicitly.
  final LoadingStyle? style;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _kSpinPeriod,
  );
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: _kMorphDuration,
  );
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: _kProgressDuration,
  );

  Animation<double>? _progressAnimation;
  late Listenable _repaint;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge(<Listenable>[_spin, _morph, _progress]);
    if (widget.status.isTerminal) {
      _morph.value = 1;
    } else {
      _spin.repeat();
    }
    if (widget.progress != null) {
      _progressAnimation = AlwaysStoppedAnimation<double>(widget.progress!);
    }
  }

  @override
  void didUpdateWidget(LoadingIndicator old) {
    super.didUpdateWidget(old);

    if (widget.status != old.status) {
      if (widget.status.isTerminal) {
        // The spin stops the moment it settles, so a finished overlay is not
        // still burning a ticker while it waits to fade out.
        _spin.stop();
        _morph.forward();
      } else {
        _morph.reverse();
        if (!_spin.isAnimating) _spin.repeat();
      }
    }

    if (widget.progress != old.progress) _retargetProgress(old.progress);
  }

  void _retargetProgress(double? previous) {
    final double? target = widget.progress;
    if (target == null) {
      _progressAnimation = null;
      _progress.stop();
      return;
    }
    final double begin = _progressAnimation?.value ?? previous ?? target;
    _progressAnimation = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _progress, curve: Curves.easeOutCubic),
    );
    _progress.forward(from: 0);
  }

  @override
  void dispose() {
    _spin.dispose();
    _morph.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ResolvedLoadingStyle resolved =
        (widget.style ?? LoadingStyle.adaptive).resolve(context);
    final double size = widget.size ?? resolved.indicatorSize;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: MorphIndicatorPainter(
            spin: _spin.value,
            morph: _morph.value,
            status: widget.status,
            progress: _progressAnimation?.value,
            color: widget.color ?? resolved.indicatorColor,
            trackColor: widget.trackColor ?? resolved.trackColor,
            successColor: widget.successColor ?? resolved.successColor,
            errorColor: widget.errorColor ?? resolved.errorColor,
            strokeWidth: widget.strokeWidth ?? resolved.indicatorStroke,
            glow: widget.glow ?? resolved.indicatorGlow,
            repaint: _repaint,
          ),
        ),
      ),
    );
  }
}
