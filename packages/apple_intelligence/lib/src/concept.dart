/// What to draw.
///
/// A concept is either something you name outright, or something you ask the
/// system to pull out of longer prose. The distinction matters: naming gives
/// you control, extraction gives you a picture of a paragraph you did not
/// write yourself, which is what makes generating an illustration for a note
/// or a message thread practical.
class ImageConcept {
  /// Names a concept directly, e.g. `'a fox reading a map'`.
  const ImageConcept.text(this.text) : title = null, extract = false;

  /// Asks the system to find the concepts in [text] itself.
  ///
  /// [title] is an optional hint about what the passage is about.
  const ImageConcept.extractedFrom(this.text, {this.title}) : extract = true;

  /// The prompt, or the prose to extract from.
  final String text;

  /// A hint for extraction. Always null for [ImageConcept.text].
  final String? title;

  /// Whether the system should extract concepts rather than take [text] as one.
  final bool extract;

  /// Wire form for the platform channel.
  Map<String, Object?> toMap() => <String, Object?>{
    'text': text,
    if (title != null) 'title': title,
    'extract': extract,
  };

  @override
  String toString() => extract
      ? 'ImageConcept.extractedFrom(${text.length} chars)'
      : 'ImageConcept.text($text)';
}

/// The visual register of a generated image.
enum ImageStyle {
  /// Rounded, animated-film look. The system default.
  animation,

  /// Flatter, illustrated look.
  illustration,

  /// Hand-drawn sketch.
  sketch;

  /// Wire form for the platform channel.
  String get wireName => name;
}
