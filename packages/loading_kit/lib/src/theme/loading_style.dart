import 'package:flutter/material.dart';

import 'loading_preset.dart';
import 'resolved_loading_style.dart';

/// A premium easing curve with a long, decelerating tail.
const Cubic _kEnterCurve = Cubic(0.16, 1.0, 0.3, 1.0);

/// The overlay's appearance: a [LoadingPreset] plus any token overrides.
///
/// Every field is optional. Unset tokens fall through to the preset, which in
/// turn resolves against the ambient [ThemeData], so light and dark both work
/// with no configuration:
///
/// ```dart
/// MaterialApp(builder: LoadingKit.builder(style: LoadingStyle.glass));
/// ```
///
/// Override only what you care about:
///
/// ```dart
/// LoadingStyle.cupertino.copyWith(
///   indicatorColor: brand.teal,
///   cardRadius: BorderRadius.circular(20),
/// )
/// ```
@immutable
class LoadingStyle {
  /// Creates a style based on [preset], overriding any tokens supplied.
  const LoadingStyle({
    this.preset = LoadingPreset.adaptive,
    this.scrimColor,
    this.backdropBlur,
    this.showCard,
    this.cardColor,
    this.cardBorderColor,
    this.cardBorderWidth,
    this.cardRadius,
    this.cardShadow,
    this.cardPadding,
    this.maxCardWidth,
    this.indicatorSize,
    this.indicatorStroke,
    this.indicatorColor,
    this.trackColor,
    this.successColor,
    this.errorColor,
    this.indicatorGlow,
    this.messageStyle,
    this.detailStyle,
    this.cancelStyle,
    this.spacing,
    this.alignment,
    this.enterCurve,
    this.exitCurve,
    this.enterScale,
  });

  /// Cupertino on Apple platforms, Material elsewhere. The default.
  static const LoadingStyle adaptive = LoadingStyle();

  /// A compact, low-contrast card in the iOS idiom.
  static const LoadingStyle cupertino = LoadingStyle(
    preset: LoadingPreset.cupertino,
  );

  /// A tonal Material 3 surface using the theme's primary colour.
  static const LoadingStyle material = LoadingStyle(
    preset: LoadingPreset.material,
  );

  /// A frosted translucent panel with a luminous edge.
  static const LoadingStyle glass = LoadingStyle(preset: LoadingPreset.glass);

  /// Indicator only, on a soft scrim. The cheapest preset to paint.
  static const LoadingStyle minimal = LoadingStyle(
    preset: LoadingPreset.minimal,
  );

  /// A dark panel with a saturated, glowing indicator.
  static const LoadingStyle neon = LoadingStyle(preset: LoadingPreset.neon);

  /// The visual language supplying tokens this style does not override.
  final LoadingPreset preset;

  /// Overrides [ResolvedLoadingStyle.scrimColor].
  final Color? scrimColor;

  /// Overrides [ResolvedLoadingStyle.backdropBlur].
  final double? backdropBlur;

  /// Overrides [ResolvedLoadingStyle.showCard].
  final bool? showCard;

  /// Overrides [ResolvedLoadingStyle.cardColor].
  final Color? cardColor;

  /// Overrides [ResolvedLoadingStyle.cardBorderColor].
  final Color? cardBorderColor;

  /// Overrides [ResolvedLoadingStyle.cardBorderWidth].
  final double? cardBorderWidth;

  /// Overrides [ResolvedLoadingStyle.cardRadius].
  final BorderRadius? cardRadius;

  /// Overrides [ResolvedLoadingStyle.cardShadow].
  final List<BoxShadow>? cardShadow;

  /// Overrides [ResolvedLoadingStyle.cardPadding].
  final EdgeInsets? cardPadding;

  /// Overrides [ResolvedLoadingStyle.maxCardWidth].
  final double? maxCardWidth;

  /// Overrides [ResolvedLoadingStyle.indicatorSize].
  final double? indicatorSize;

  /// Overrides [ResolvedLoadingStyle.indicatorStroke].
  final double? indicatorStroke;

  /// Overrides [ResolvedLoadingStyle.indicatorColor].
  final Color? indicatorColor;

  /// Overrides [ResolvedLoadingStyle.trackColor].
  final Color? trackColor;

  /// Overrides [ResolvedLoadingStyle.successColor].
  final Color? successColor;

  /// Overrides [ResolvedLoadingStyle.errorColor].
  final Color? errorColor;

  /// Overrides [ResolvedLoadingStyle.indicatorGlow].
  final double? indicatorGlow;

  /// Overrides [ResolvedLoadingStyle.messageStyle].
  final TextStyle? messageStyle;

  /// Overrides [ResolvedLoadingStyle.detailStyle].
  final TextStyle? detailStyle;

  /// Overrides [ResolvedLoadingStyle.cancelStyle].
  final TextStyle? cancelStyle;

  /// Overrides [ResolvedLoadingStyle.spacing].
  final double? spacing;

  /// Overrides [ResolvedLoadingStyle.alignment].
  final Alignment? alignment;

  /// Overrides [ResolvedLoadingStyle.enterCurve].
  final Curve? enterCurve;

  /// Overrides [ResolvedLoadingStyle.exitCurve].
  final Curve? exitCurve;

  /// Overrides [ResolvedLoadingStyle.enterScale].
  final double? enterScale;

  /// Returns a copy with the given fields replaced.
  LoadingStyle copyWith({
    LoadingPreset? preset,
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
    return LoadingStyle(
      preset: preset ?? this.preset,
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

  /// Resolves every token against [context], applying overrides last.
  ResolvedLoadingStyle resolve(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ResolvedLoadingStyle base = _baseFor(_effectivePreset(theme), theme);
    return base.copyWith(
      scrimColor: scrimColor,
      backdropBlur: backdropBlur,
      showCard: showCard,
      cardColor: cardColor,
      cardBorderColor: cardBorderColor,
      cardBorderWidth: cardBorderWidth,
      cardRadius: cardRadius,
      cardShadow: cardShadow,
      cardPadding: cardPadding,
      maxCardWidth: maxCardWidth,
      indicatorSize: indicatorSize,
      indicatorStroke: indicatorStroke,
      indicatorColor: indicatorColor,
      trackColor: trackColor,
      successColor: successColor,
      errorColor: errorColor,
      indicatorGlow: indicatorGlow,
      messageStyle: messageStyle,
      detailStyle: detailStyle,
      cancelStyle: cancelStyle,
      spacing: spacing,
      alignment: alignment,
      enterCurve: enterCurve,
      exitCurve: exitCurve,
      enterScale: enterScale,
    );
  }

  LoadingPreset _effectivePreset(ThemeData theme) {
    if (preset != LoadingPreset.adaptive) return preset;
    return switch (theme.platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => LoadingPreset.cupertino,
      _ => LoadingPreset.material,
    };
  }

  static ResolvedLoadingStyle _baseFor(LoadingPreset preset, ThemeData theme) {
    return switch (preset) {
      LoadingPreset.cupertino => _cupertino(theme),
      LoadingPreset.glass => _glass(theme),
      LoadingPreset.minimal => _minimal(theme),
      LoadingPreset.neon => _neon(theme),
      LoadingPreset.material || LoadingPreset.adaptive => _material(theme),
    };
  }

  static ResolvedLoadingStyle _cupertino(ThemeData theme) {
    final bool dark = theme.brightness == Brightness.dark;
    final Color onCard = dark
        ? const Color(0xFFF2F2F7)
        : const Color(0xFF1C1C1E);
    return ResolvedLoadingStyle(
      scrimColor: const Color(0xFF000000).withValues(alpha: dark ? 0.38 : 0.20),
      backdropBlur: 0,
      showCard: true,
      cardColor: dark
          ? const Color(0xFF1C1C1E).withValues(alpha: 0.96)
          : const Color(0xFFF7F7FA).withValues(alpha: 0.98),
      cardBorderColor: dark
          ? const Color(0xFFFFFFFF).withValues(alpha: 0.08)
          : null,
      cardBorderWidth: 1,
      cardRadius: const BorderRadius.all(Radius.circular(16)),
      cardShadow: <BoxShadow>[
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: dark ? 0.44 : 0.14),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
      cardPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      maxCardWidth: 260,
      indicatorSize: 30,
      indicatorStroke: 3,
      indicatorColor: dark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93),
      trackColor: onCard.withValues(alpha: 0.12),
      successColor: const Color(0xFF34C759),
      errorColor: const Color(0xFFFF3B30),
      indicatorGlow: 0,
      messageStyle: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: onCard,
      ),
      detailStyle: TextStyle(
        fontSize: 13,
        height: 1.3,
        color: onCard.withValues(alpha: 0.6),
      ),
      cancelStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0A84FF),
      ),
      spacing: 14,
      alignment: Alignment.center,
      enterCurve: _kEnterCurve,
      exitCurve: Curves.easeInCubic,
      enterScale: 0.90,
    );
  }

  static ResolvedLoadingStyle _material(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    return ResolvedLoadingStyle(
      scrimColor: scheme.scrim.withValues(alpha: dark ? 0.50 : 0.32),
      backdropBlur: 0,
      showCard: true,
      cardColor: scheme.surfaceContainerHigh,
      cardBorderColor: scheme.outlineVariant.withValues(alpha: 0.5),
      cardBorderWidth: 1,
      cardRadius: const BorderRadius.all(Radius.circular(28)),
      cardShadow: <BoxShadow>[
        BoxShadow(
          color: scheme.shadow.withValues(alpha: dark ? 0.46 : 0.18),
          blurRadius: 34,
          offset: const Offset(0, 12),
        ),
      ],
      cardPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      maxCardWidth: 280,
      indicatorSize: 40,
      indicatorStroke: 4,
      indicatorColor: scheme.primary,
      trackColor: scheme.primary.withValues(alpha: 0.16),
      successColor: dark ? const Color(0xFF7BE08F) : const Color(0xFF2E7D32),
      errorColor: scheme.error,
      indicatorGlow: 0,
      messageStyle: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: scheme.onSurface,
      ),
      detailStyle: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: scheme.onSurfaceVariant,
      ),
      cancelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: scheme.primary,
      ),
      spacing: 16,
      alignment: Alignment.center,
      enterCurve: _kEnterCurve,
      exitCurve: Curves.easeInCubic,
      enterScale: 0.92,
    );
  }

  static ResolvedLoadingStyle _glass(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final Color onCard = dark ? Colors.white : const Color(0xFF11151C);
    return ResolvedLoadingStyle(
      scrimColor: const Color(0xFF000000).withValues(alpha: dark ? 0.42 : 0.32),
      backdropBlur: 18,
      showCard: true,
      cardColor: dark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.74),
      cardBorderColor: Colors.white.withValues(alpha: dark ? 0.22 : 0.85),
      cardBorderWidth: 1,
      cardRadius: const BorderRadius.all(Radius.circular(26)),
      cardShadow: <BoxShadow>[
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: dark ? 0.40 : 0.16),
          blurRadius: 44,
          offset: const Offset(0, 18),
        ),
      ],
      cardPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      maxCardWidth: 280,
      indicatorSize: 38,
      indicatorStroke: 3.5,
      indicatorColor: dark ? Colors.white : scheme.primary,
      trackColor: onCard.withValues(alpha: 0.14),
      successColor: const Color(0xFF32D583),
      errorColor: const Color(0xFFFF5A5F),
      indicatorGlow: 10,
      messageStyle: TextStyle(
        fontSize: 15.5,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onCard,
      ),
      detailStyle: TextStyle(
        fontSize: 13,
        height: 1.35,
        color: onCard.withValues(alpha: 0.64),
      ),
      cancelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: onCard.withValues(alpha: 0.85),
      ),
      spacing: 16,
      alignment: Alignment.center,
      enterCurve: _kEnterCurve,
      exitCurve: Curves.easeInCubic,
      enterScale: 0.94,
    );
  }

  static ResolvedLoadingStyle _minimal(ThemeData theme) {
    final ColorScheme scheme = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    final Color ink = dark ? Colors.white : const Color(0xFF11151C);
    return ResolvedLoadingStyle(
      scrimColor: (dark ? Colors.black : Colors.white).withValues(
        alpha: dark ? 0.62 : 0.80,
      ),
      backdropBlur: 0,
      showCard: false,
      cardColor: const Color(0x00000000),
      cardBorderColor: null,
      cardBorderWidth: 0,
      cardRadius: BorderRadius.zero,
      cardShadow: const <BoxShadow>[],
      cardPadding: const EdgeInsets.all(8),
      maxCardWidth: 260,
      indicatorSize: 34,
      indicatorStroke: 2.5,
      indicatorColor: scheme.primary,
      trackColor: ink.withValues(alpha: 0.12),
      successColor: const Color(0xFF2FA96B),
      errorColor: scheme.error,
      indicatorGlow: 0,
      messageStyle: TextStyle(
        fontSize: 14.5,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: ink.withValues(alpha: 0.86),
      ),
      detailStyle: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: ink.withValues(alpha: 0.55),
      ),
      cancelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.primary,
      ),
      spacing: 14,
      alignment: Alignment.center,
      enterCurve: _kEnterCurve,
      exitCurve: Curves.easeInCubic,
      enterScale: 0.88,
    );
  }

  static ResolvedLoadingStyle _neon(ThemeData theme) {
    const Color accent = Color(0xFF22E3FF);
    return ResolvedLoadingStyle(
      scrimColor: const Color(0xFF04060C).withValues(alpha: 0.74),
      backdropBlur: 6,
      showCard: true,
      cardColor: const Color(0xFF0A0F1B).withValues(alpha: 0.94),
      cardBorderColor: accent.withValues(alpha: 0.42),
      cardBorderWidth: 1,
      cardRadius: const BorderRadius.all(Radius.circular(20)),
      cardShadow: <BoxShadow>[
        BoxShadow(
          color: accent.withValues(alpha: 0.20),
          blurRadius: 46,
          spreadRadius: -6,
        ),
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: 0.60),
          blurRadius: 30,
          offset: const Offset(0, 14),
        ),
      ],
      cardPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      maxCardWidth: 280,
      indicatorSize: 38,
      indicatorStroke: 3,
      indicatorColor: accent,
      trackColor: accent.withValues(alpha: 0.14),
      successColor: const Color(0xFF3DFFA0),
      errorColor: const Color(0xFFFF3D71),
      indicatorGlow: 16,
      messageStyle: const TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        color: Color(0xFFE8FBFF),
      ),
      detailStyle: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        letterSpacing: 0.2,
        color: const Color(0xFFE8FBFF).withValues(alpha: 0.58),
      ),
      cancelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: accent,
      ),
      spacing: 16,
      alignment: Alignment.center,
      enterCurve: _kEnterCurve,
      exitCurve: Curves.easeInCubic,
      enterScale: 0.92,
    );
  }
}
