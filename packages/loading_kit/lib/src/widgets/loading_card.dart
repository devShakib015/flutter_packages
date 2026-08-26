import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/loading_state.dart';
import '../theme/loading_indicator_builder.dart';
import '../theme/loading_progress_style.dart';
import '../theme/resolved_loading_style.dart';
import 'loading_indicator.dart';
import 'loading_progress_bar.dart';

/// The panel holding the indicator, the text, and the cancel affordance.
///
/// Rendered by the overlay. Exposed so it can be embedded directly — inside a
/// card placeholder, say — without the surrounding scrim.
class LoadingCard extends StatelessWidget {
  /// Creates a card rendering [state] with [style].
  const LoadingCard({
    super.key,
    required this.state,
    required this.style,
    this.onCancel,
    this.cancelLabel = 'Cancel',
  });

  /// What to render.
  final LoadingState state;

  /// Resolved visual tokens.
  final ResolvedLoadingStyle style;

  /// Invoked when the cancel affordance is tapped.
  final VoidCallback? onCancel;

  /// Label of the cancel affordance.
  final String cancelLabel;

  /// Chooses between a custom indicator, a progress bar, and the built-in
  /// circular form.
  Widget _buildIndicator(BuildContext context) {
    final LoadingIndicatorBuilder? builder = style.indicatorBuilder;
    if (builder != null) {
      return builder(
        context,
        LoadingIndicatorSpec(
          status: state.status,
          progress: state.progress,
          size: style.indicatorSize,
          color: style.indicatorColor,
          trackColor: style.trackColor,
          successColor: style.successColor,
          errorColor: style.errorColor,
          strokeWidth: style.indicatorStroke,
        ),
      );
    }

    final Widget circular = LoadingIndicator(
      status: state.status,
      progress: state.progress,
      size: style.indicatorSize,
      strokeWidth: style.indicatorStroke,
      color: style.indicatorColor,
      trackColor: style.trackColor,
      successColor: style.successColor,
      errorColor: style.errorColor,
      glow: style.indicatorGlow,
      indicatorStyle: style.indicatorStyle,
    );

    if (style.progressStyle != LoadingProgressStyle.bar) return circular;

    // A bar cannot express success or failure, so the outcome still arrives as
    // the glyph. Cross-fade rather than swap so the change reads as one move.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: state.status.isTerminal
          ? circular
          : LoadingProgressBar(
              key: const ValueKey<String>('bar'),
              progress: state.progress,
              status: state.status,
              color: style.indicatorColor,
              trackColor: style.trackColor,
              successColor: style.successColor,
              errorColor: style.errorColor,
              width: style.maxCardWidth - style.cardPadding.horizontal,
              thickness: style.indicatorStroke * 1.6,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildIndicator(context),
        if (state.message != null) ...<Widget>[
          SizedBox(height: style.spacing),
          Text(
            state.message!,
            textAlign: TextAlign.center,
            style: style.messageStyle,
          ),
        ],
        if (state.detail != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            state.detail!,
            textAlign: TextAlign.center,
            style: style.detailStyle,
          ),
        ],
        if (state.cancellable && onCancel != null) ...<Widget>[
          SizedBox(height: style.spacing * 0.75),
          _CancelButton(
            label: cancelLabel,
            style: style.cancelStyle,
            onPressed: onCancel!,
          ),
        ],
      ],
    );

    if (!style.showCard) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: style.maxCardWidth),
        child: Padding(padding: style.cardPadding, child: content),
      );
    }

    final Widget card = Container(
      constraints: BoxConstraints(
        maxWidth: style.maxCardWidth,
        minWidth: state.hasText ? 132 : 0,
      ),
      padding: style.cardPadding,
      decoration: BoxDecoration(
        color: style.cardColor,
        borderRadius: style.cardRadius,
        border: style.cardBorderColor == null
            ? null
            : Border.all(
                color: style.cardBorderColor!,
                width: style.cardBorderWidth,
              ),
        boxShadow: style.cardShadow,
      ),
      child: content,
    );

    if (style.backdropBlur <= 0) return card;

    // The blur is clipped to the card so the filter samples only the area it
    // actually tints, rather than compositing the whole screen.
    return ClipRRect(
      borderRadius: style.cardRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: style.backdropBlur,
          sigmaY: style.backdropBlur,
        ),
        child: card,
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: style.color,
        ),
        child: Text(label, style: style),
      ),
    );
  }
}
