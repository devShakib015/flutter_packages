import 'package:flutter/widgets.dart';

/// Appearance of a transient message.
///
/// Toasts otherwise inherit the card tokens — fill, border, shadow and text
/// styles — so they match the overlay without being configured twice. These
/// are the handful of metrics that only make sense for a toast.
@immutable
class LoadingToastStyle {
  /// Creates a toast style.
  const LoadingToastStyle({
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.radius,
    this.iconSize = 20,
    this.iconStroke = 2.2,
    this.iconGap = 12,
    this.gap = 8,
    this.enterDuration = const Duration(milliseconds: 260),
  });

  /// Inner padding of the chip.
  final EdgeInsets padding;

  /// Corner radius. Null derives one from the card radius.
  final BorderRadius? radius;

  /// Diameter of the leading status glyph.
  final double iconSize;

  /// Stroke width of the leading status glyph.
  final double iconStroke;

  /// Gap between the glyph and the text.
  final double iconGap;

  /// Vertical gap between stacked toasts.
  final double gap;

  /// How long a toast takes to animate in.
  ///
  /// The matching exit duration lives on `LoadingController`, which owns when
  /// a toast is actually removed.
  final Duration enterDuration;

  /// Returns a copy with the given fields replaced.
  LoadingToastStyle copyWith({
    EdgeInsets? padding,
    BorderRadius? radius,
    double? iconSize,
    double? iconStroke,
    double? iconGap,
    double? gap,
    Duration? enterDuration,
  }) {
    return LoadingToastStyle(
      padding: padding ?? this.padding,
      radius: radius ?? this.radius,
      iconSize: iconSize ?? this.iconSize,
      iconStroke: iconStroke ?? this.iconStroke,
      iconGap: iconGap ?? this.iconGap,
      gap: gap ?? this.gap,
      enterDuration: enterDuration ?? this.enterDuration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadingToastStyle &&
          other.padding == padding &&
          other.radius == radius &&
          other.iconSize == iconSize &&
          other.iconStroke == iconStroke &&
          other.iconGap == iconGap &&
          other.gap == gap &&
          other.enterDuration == enterDuration;

  @override
  int get hashCode => Object.hash(
    padding,
    radius,
    iconSize,
    iconStroke,
    iconGap,
    gap,
    enterDuration,
  );
}
