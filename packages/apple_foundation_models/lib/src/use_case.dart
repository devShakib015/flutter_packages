/// Which flavour of the on-device model to talk to.
///
/// Apple ships a general model plus narrower ones tuned for specific jobs. The
/// specialised variants are smaller and sharper at their task, so picking the
/// right one beats prompting the general model harder.
enum ModelUseCase {
  /// The general-purpose model. The right default.
  general,

  /// Tuned for producing tags, topics, and categories from text.
  ///
  /// Prefer this over [general] whenever the job is labelling rather than
  /// writing. Pair it with `Schema.oneOf` or an array of strings.
  contentTagging;

  /// Wire representation.
  String get wireName => name;
}
