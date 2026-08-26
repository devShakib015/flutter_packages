/// Text that shrinks to fit its box — correctly, including inside
/// `IntrinsicHeight`, `IntrinsicWidth` and `Table` cells.
///
/// ```dart
/// FitText('A headline that must never wrap', maxLines: 1, minFontSize: 12)
/// ```
library;

export 'src/fit_text.dart';
export 'src/fit_text_group.dart';
export 'src/render_fit_text.dart' show RenderFitText;
