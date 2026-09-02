import 'package:flutter/material.dart';

import '../core/loading_status.dart';
import '../painting/loading_indicator_painter.dart';
import '../theme/loading_indicator_style.dart';
import '../theme/loading_motion.dart';
import '../theme/loading_style.dart';
import '../theme/resolved_loading_style.dart';

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
    this.indicatorStyle,
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

  /// The indeterminate form to draw. Falls back to the resolved style.
  ///
  /// Ignored while [progress] is set: determinate work is always an arc,
  /// because no pulsing or bouncing form can express a proportion.
  final LoadingIndicatorStyle? indicatorStyle;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this);
  late final AnimationController _morph = AnimationController(vsync: this);

  /// The terminal status the current morph belongs to.
  ///
  /// The painter derives its colour and glyph from the status it is given, so
  /// once the overlay flipped back to busy while the morph was still running
  /// out, an error cross recoloured itself into a green success tick on its
  /// way off the screen. Holding the terminal identity for the length of the
  /// morph keeps the glyph honest.
  LoadingStatus? _lastTerminal;
  late final AnimationController _progress = AnimationController(vsync: this);

  Animation<double>? _progressAnimation;
  late Listenable _repaint;
  ResolvedLoadingStyle? _resolved;
  LoadingMotion? _appliedMotion;

  @override
  void initState() {
    super.initState();
    _repaint = Listenable.merge(<Listenable>[_spin, _morph, _progress]);
    if (widget.progress != null) {
      _progressAnimation = AlwaysStoppedAnimation<double>(widget.progress!);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  void _resolve() {
    _resolved = (widget.style ?? LoadingStyle.adaptive).resolve(context);
    _applyMotion();
  }

  /// Pushes the resolved motion profile onto the controllers.
  ///
  /// Changing an [AnimationController]'s duration mid-cycle does not retime a
  /// repeat already in flight, so a changed profile restarts the spin.
  void _applyMotion() {
    final LoadingMotion motion = _resolved!.motion;
    final bool changed = _appliedMotion != null && _appliedMotion != motion;
    _appliedMotion = motion;

    _spin.duration = motion.spinPeriod;
    _morph.duration = motion.morphDuration;
    _progress.duration = motion.progressDuration;

    if (widget.status.isTerminal) {
      _lastTerminal = widget.status;
      if (_morph.isDismissed) _morph.value = 1;
      _spin.stop();
    } else if (!_spin.isAnimating || changed) {
      _spin.repeat();
    }
  }

  @override
  void didUpdateWidget(LoadingIndicator old) {
    super.didUpdateWidget(old);

    if (widget.status != old.status) {
      if (widget.status.isTerminal) {
        _lastTerminal = widget.status;
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
    if (widget.style != old.style) _resolve();
  }

  void _retargetProgress(double? previous) {
    final double? target = widget.progress;
    if (target == null) {
      _progressAnimation = null;
      _progress.stop();
      return;
    }
    final double begin = _progressAnimation?.value ?? previous ?? target;
    _progressAnimation = Tween<double>(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(parent: _progress, curve: Curves.easeOutCubic));
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
    final ResolvedLoadingStyle resolved = _resolved!;
    final double size = widget.size ?? resolved.indicatorSize;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _repaint,
          builder: (BuildContext context, Widget? _) => CustomPaint(
            painter: LoadingIndicatorPainter(
              style: widget.indicatorStyle ?? resolved.indicatorStyle,
              spin: _spin.value,
              morph: _morph.value,
              status: !widget.status.isTerminal && _morph.value > 0
                  ? (_lastTerminal ?? widget.status)
                  : widget.status,
              progress: _progressAnimation?.value,
              color: widget.color ?? resolved.indicatorColor,
              trackColor: widget.trackColor ?? resolved.trackColor,
              successColor: widget.successColor ?? resolved.successColor,
              errorColor: widget.errorColor ?? resolved.errorColor,
              strokeWidth: widget.strokeWidth ?? resolved.indicatorStroke,
              glow: widget.glow ?? resolved.indicatorGlow,
            ),
          ),
        ),
      ),
    );
  }
}
