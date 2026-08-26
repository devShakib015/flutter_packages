import 'package:flutter/material.dart';

import '../core/loading_controller.dart';
import '../core/loading_status.dart';
import '../core/loading_toast.dart';
import '../theme/loading_style.dart';
import '../theme/resolved_loading_style.dart';
import 'loading_indicator.dart';

/// Renders a controller's transient messages.
///
/// Never blocks input: the whole layer is wrapped in an [IgnorePointer], and
/// it builds nothing at all when there are no toasts.
class LoadingToastLayer extends StatelessWidget {
  /// Creates a toast layer driven by [controller].
  const LoadingToastLayer({
    super.key,
    required this.controller,
    this.style = LoadingStyle.adaptive,
    this.alignment = Alignment.bottomCenter,
    this.padding = const EdgeInsets.all(20),
  });

  /// Supplies the toasts.
  final LoadingController controller;

  /// Appearance, reusing the overlay's card tokens.
  final LoadingStyle style;

  /// Where the stack of toasts sits.
  final Alignment alignment;

  /// Inset from the safe area.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<LoadingToast>>(
      valueListenable: controller.toasts,
      builder: (BuildContext context, List<LoadingToast> toasts, Widget? _) {
        if (toasts.isEmpty) return const SizedBox.shrink();
        final ResolvedLoadingStyle resolved = style.resolve(context);
        return IgnorePointer(
          child: SafeArea(
            child: Padding(
              padding: padding,
              child: Align(
                alignment: alignment,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    for (final LoadingToast toast in toasts)
                      _ToastChip(
                        key: ValueKey<Object>(toast.id),
                        toast: toast,
                        style: resolved,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ToastChip extends StatefulWidget {
  const _ToastChip({super.key, required this.toast, required this.style});

  final LoadingToast toast;
  final ResolvedLoadingStyle style;

  @override
  State<_ToastChip> createState() => _ToastChipState();
}

class _ToastChipState extends State<_ToastChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: LoadingController.toastExitDuration,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.toast.dismissing) _reveal.forward();
  }

  @override
  void didUpdateWidget(_ToastChip old) {
    super.didUpdateWidget(old);
    if (widget.toast.dismissing && !old.toast.dismissing) _reveal.reverse();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ResolvedLoadingStyle style = widget.style;
    final LoadingStatus? status = widget.toast.status;

    return AnimatedBuilder(
      animation: _reveal,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeOutCubic.transform(_reveal.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: Align(heightFactor: t, child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          constraints: BoxConstraints(maxWidth: style.maxCardWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: style.cardColor,
            borderRadius: BorderRadius.circular(
              style.cardRadius.topLeft.x.clamp(12.0, 22.0),
            ),
            border: style.cardBorderColor == null
                ? null
                : Border.all(
                    color: style.cardBorderColor!,
                    width: style.cardBorderWidth,
                  ),
            boxShadow: style.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (status != null) ...<Widget>[
                LoadingIndicator(
                  status: status,
                  size: 20,
                  strokeWidth: 2.2,
                  color: style.indicatorColor,
                  trackColor: const Color(0x00000000),
                  successColor: style.successColor,
                  errorColor: style.errorColor,
                ),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.toast.message, style: style.messageStyle),
                    if (widget.toast.detail != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.toast.detail!,
                          style: style.detailStyle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
