/// The shape the indicator takes while work is in progress.
///
/// This governs the *indeterminate* animation only. Determinate progress is
/// always drawn as an arc or a bar, because those are the only forms that read
/// as a proportion — see `LoadingProgressStyle`.
///
/// Every style settles into the same check or cross when the work finishes, so
/// the terminal feedback stays consistent across a codebase.
enum LoadingIndicatorStyle {
  /// A sweeping arc that closes seamlessly into the terminal glyph.
  ///
  /// The default, and the only style whose busy and terminal forms are one
  /// continuous shape rather than a cross-fade.
  arc,

  /// Three dots pulsing in sequence.
  dots,

  /// Four bars rising and falling like an equaliser.
  bars,

  /// A dot travelling around a faint ring.
  orbit,

  /// A filled disc breathing in and out.
  pulse,

  /// Concentric rings expanding outward and fading.
  ripple,
}
