/// The built-in visual languages the overlay can wear.
///
/// A preset supplies every token; [LoadingStyle] then overrides individual
/// ones. Presets resolve against the ambient [ThemeData], so each has a
/// correct light and dark form without any configuration.
enum LoadingPreset {
  /// [cupertino] on iOS and macOS, [material] everywhere else.
  adaptive,

  /// A compact, low-contrast card in the iOS idiom. Quiet and unobtrusive.
  cupertino,

  /// A tonal Material 3 surface with a generous radius and the primary colour.
  material,

  /// A frosted, translucent panel with a luminous edge. Uses a backdrop blur,
  /// which costs more to paint than the other presets.
  glass,

  /// No card at all — the indicator floats on a soft scrim. The lightest
  /// possible treatment, and the cheapest to paint.
  minimal,

  /// A dark panel with a saturated, glowing indicator.
  neon,
}
