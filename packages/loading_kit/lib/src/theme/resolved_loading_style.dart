import 'package:flutter/widgets.dart';

/// A fully-specified set of visual tokens, with no nulls left to resolve.
///
/// Produced by `LoadingStyle.resolve` and consumed by the overlay widgets.
/// Resolution happens once per style or theme change rather than per frame.
@immutable
class ResolvedLoadingStyle {
  /// Creates a resolved style. Every token is required.
  const ResolvedLoadingStyle({
    required this.scrimColor,
    required this.backdropBlur,
    required this.showCard,
    required this.cardColor,
    required this.cardBorderColor,
    required this.cardBorderWidth,
    required this.cardRadius,
    required this.cardShadow,
    required this.cardPadding,
    required this.maxCardWidth,
    required this.indicatorSize,
    required this.indicatorStroke,
    required this.indicatorColor,
    required this.trackColor,
    required this.successColor,
    required this.errorColor,
    required this.indicatorGlow,
    required this.messageStyle,
    required this.detailStyle,
    required this.cancelStyle,
    required this.spacing,
    required this.alignment,
    required this.enterCurve,
    required this.exitCurve,
    required this.enterScale,
  });

  /// Colour painted over the app behind the card.
  final Color scrimColor;

  /// Gaussian blur sigma applied to whatever shows through the card.
  ///
  /// The filter is clipped to the card rather than run over the whole screen,
  /// so it samples only the area it actually tints. Zero skips
  /// [BackdropFilter] entirely — worth keeping at zero on low-end devices,
  /// where blur is the most expensive thing this package can do.
  final double backdropBlur;

  /// Whether to paint a card behind the indicator and text.
  final bool showCard;

  /// Fill colour of the card.
  final Color cardColor;

  /// Colour of the card's hairline border, or null for no border.
  final Color? cardBorderColor;

  /// Width of the card's border.
  final double cardBorderWidth;

  /// Corner radius of the card.
  final BorderRadius cardRadius;

  /// Shadows cast by the card.
  final List<BoxShadow> cardShadow;

  /// Inner padding of the card.
  final EdgeInsets cardPadding;

  /// Maximum width the card may grow to before text wraps.
  final double maxCardWidth;

  /// Diameter of the indicator.
  final double indicatorSize;

  /// Stroke width of the indicator arc and glyphs.
  final double indicatorStroke;

  /// Colour of the arc while busy.
  final Color indicatorColor;

  /// Colour of the unfilled track behind the arc.
  final Color trackColor;

  /// Colour the arc becomes on success.
  final Color successColor;

  /// Colour the arc becomes on error.
  final Color errorColor;

  /// Blur radius of a glow drawn under the arc. Zero disables the glow.
  final double indicatorGlow;

  /// Text style of the primary message.
  final TextStyle messageStyle;

  /// Text style of the secondary detail line.
  final TextStyle detailStyle;

  /// Text style of the cancel affordance.
  final TextStyle cancelStyle;

  /// Vertical gap between the indicator and the text block.
  final double spacing;

  /// Where the card sits within the screen.
  final Alignment alignment;

  /// Curve of the entrance transition.
  final Curve enterCurve;

  /// Curve of the exit transition.
  final Curve exitCurve;

  /// Scale the card starts at when entering. 1.0 disables the scale.
  final double enterScale;

  /// Returns a copy with the given tokens replaced.
  ResolvedLoadingStyle copyWith({
    Color? scrimColor,
    double? backdropBlur,
    bool? showCard,
    Color? cardColor,
    Color? cardBorderColor,
    double? cardBorderWidth,
    BorderRadius? cardRadius,
    List<BoxShadow>? cardShadow,
    EdgeInsets? cardPadding,
    double? maxCardWidth,
    double? indicatorSize,
    double? indicatorStroke,
    Color? indicatorColor,
    Color? trackColor,
    Color? successColor,
    Color? errorColor,
    double? indicatorGlow,
    TextStyle? messageStyle,
    TextStyle? detailStyle,
    TextStyle? cancelStyle,
    double? spacing,
    Alignment? alignment,
    Curve? enterCurve,
    Curve? exitCurve,
    double? enterScale,
  }) {
    return ResolvedLoadingStyle(
      scrimColor: scrimColor ?? this.scrimColor,
      backdropBlur: backdropBlur ?? this.backdropBlur,
      showCard: showCard ?? this.showCard,
      cardColor: cardColor ?? this.cardColor,
      cardBorderColor: cardBorderColor ?? this.cardBorderColor,
      cardBorderWidth: cardBorderWidth ?? this.cardBorderWidth,
      cardRadius: cardRadius ?? this.cardRadius,
      cardShadow: cardShadow ?? this.cardShadow,
      cardPadding: cardPadding ?? this.cardPadding,
      maxCardWidth: maxCardWidth ?? this.maxCardWidth,
      indicatorSize: indicatorSize ?? this.indicatorSize,
      indicatorStroke: indicatorStroke ?? this.indicatorStroke,
      indicatorColor: indicatorColor ?? this.indicatorColor,
      trackColor: trackColor ?? this.trackColor,
      successColor: successColor ?? this.successColor,
      errorColor: errorColor ?? this.errorColor,
      indicatorGlow: indicatorGlow ?? this.indicatorGlow,
      messageStyle: messageStyle ?? this.messageStyle,
      detailStyle: detailStyle ?? this.detailStyle,
      cancelStyle: cancelStyle ?? this.cancelStyle,
      spacing: spacing ?? this.spacing,
      alignment: alignment ?? this.alignment,
      enterCurve: enterCurve ?? this.enterCurve,
      exitCurve: exitCurve ?? this.exitCurve,
      enterScale: enterScale ?? this.enterScale,
    );
  }
}
