import 'package:flutter/material.dart';

import '../core/loading_controller.dart';
import '../core/loading_state.dart';
import '../core/loading_status.dart';
import '../theme/loading_style.dart';
import '../theme/resolved_loading_style.dart';
import 'loading_card.dart';

/// Renders a [LoadingController] as a scrim and a card.
///
/// Costs nothing while idle. When no operation is painted and no transition is
/// running this builds a zero-sized box: no scrim, no blur, no ticker. That is
/// what makes it safe to leave installed above every route in the app.
class LoadingOverlay extends StatefulWidget {
  /// Creates an overlay driven by [controller].
  const LoadingOverlay({
    super.key,
    required this.controller,
    this.style = LoadingStyle.adaptive,
    this.cancelLabel = 'Cancel',
    this.busySemanticsLabel = 'Busy',
  });

  /// The controller supplying state.
  final LoadingController controller;

  /// Appearance of the scrim and card.
  final LoadingStyle style;

  /// Label of the cancel affordance.
  final String cancelLabel;

  /// Announced to screen readers when no message is set.
  final String busySemanticsLabel;

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: widget.controller.timing.enter,
    reverseDuration: widget.controller.timing.exit,
  );

  LoadingState _state = LoadingState.idle;

  /// The last painted state, kept so the exit transition animates real content
  /// instead of collapsing to an empty card the instant work finishes.
  LoadingState _painted = LoadingState.idle;

  @override
  void initState() {
    super.initState();
    _state = widget.controller.value;
    if (_state.visible) {
      _painted = _state;
      _reveal.value = 1;
    }
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(LoadingOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  void _onControllerChanged() {
    final LoadingState next = widget.controller.value;
    if (next == _state) return;
    setState(() {
      _state = next;
      if (next.visible) _painted = next;
    });
    if (next.visible) {
      _reveal.forward();
    } else {
      _reveal.reverse();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _reveal.dispose();
    super.dispose();
  }

  void _handleCancel() => widget.controller.cancelTopmost();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (BuildContext context, Widget? _) {
        // The idle fast path. Nothing is built, so nothing is painted and
        // nothing is hit-tested.
        if (!_state.visible && _reveal.isDismissed) {
          return const SizedBox.shrink();
        }

        final ResolvedLoadingStyle style = widget.style.resolve(context);
        final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
        final bool entering = _state.visible;
        final Curve curve = entering ? style.enterCurve : style.exitCurve;
        final double t = curve.transform(_reveal.value.clamp(0.0, 1.0));

        final LoadingState painted = entering ? _state : _painted;
        // On the way out the card is a ghost of the last state; it must not
        // still accept taps.
        final bool canCancel =
            entering && (painted.cancellable || painted.dismissible);

        return Semantics(
          container: true,
          liveRegion: true,
          // The card's own Text already supplies the label, and these nodes
          // merge — labelling here too would have a screen reader read the
          // message twice. Only stand in when there is no text to read.
          label: painted.message == null ? widget.busySemanticsLabel : null,
          value: painted.progress == null
              ? null
              : '${(painted.progress! * 100).round()}%',
          child: BlockSemantics(
            child: Stack(
              alignment: Alignment.topLeft,
              fit: StackFit.expand,
              children: <Widget>[
                // An opaque hit target swallows every tap bound for the app
                // behind it, which is the whole point of a blocking overlay.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: entering && painted.dismissible ? _handleCancel : null,
                  child: ColoredBox(
                    color: style.scrimColor.withValues(
                      alpha: style.scrimColor.a * t,
                    ),
                  ),
                ),
                Align(
                  alignment: style.alignment,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      scale: reduceMotion
                          ? 1.0
                          : style.enterScale + (1 - style.enterScale) * t,
                      child: LoadingCard(
                        state: painted,
                        style: style,
                        cancelLabel: widget.cancelLabel,
                        onCancel: canCancel ? _handleCancel : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Convenience predicate used by tests and by callers inspecting a snapshot.
extension LoadingStateX on LoadingState {
  /// Whether the indicator has settled into a check mark.
  bool get isSuccess => status == LoadingStatus.success;

  /// Whether the indicator has settled into a cross.
  bool get isError => status == LoadingStatus.error;
}
