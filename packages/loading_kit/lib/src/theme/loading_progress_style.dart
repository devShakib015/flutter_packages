/// How determinate progress is drawn.
enum LoadingProgressStyle {
  /// A circular arc filling clockwise. Compact, and matches the busy spinner.
  ring,

  /// A horizontal bar filling left to right.
  ///
  /// Easier to read at a glance for long operations such as uploads, where the
  /// difference between 60% and 70% matters. Terminal feedback still uses the
  /// glyph, so a finished bar cross-fades to a check or a cross.
  bar,
}
