/// Why image generation is or is not usable right now.
enum ImageGenerationStatus {
  /// Generation is usable.
  available,

  /// The OS is new enough, but this device cannot generate — Apple
  /// Intelligence is off, unsupported, or still downloading.
  unavailable,

  /// The system predates Image Playground, or the app was built without it.
  osTooOld,
}

/// What this device can actually do, asked as separate questions because the
/// answers differ.
///
/// The system sheet arrived in iOS 18.1, and generating without any UI arrived
/// in 18.4, so a device can perfectly well offer one and not the other. Code
/// that assumes a single yes/no will be wrong on real hardware.
class ImageGenerationAvailability {
  /// Creates an availability report.
  const ImageGenerationAvailability({
    required this.status,
    required this.sheet,
    required this.creator,
  });

  /// Builds a report from the platform's reply.
  factory ImageGenerationAvailability.fromMap(Map<Object?, Object?> map) {
    return ImageGenerationAvailability(
      status: switch (map['status'] as String?) {
        'available' => ImageGenerationStatus.available,
        'osTooOld' => ImageGenerationStatus.osTooOld,
        _ => ImageGenerationStatus.unavailable,
      },
      sheet: map['sheet'] as bool? ?? false,
      creator: map['creator'] as bool? ?? false,
    );
  }

  /// Why generation is or is not usable.
  final ImageGenerationStatus status;

  /// Whether the Image Playground sheet can be presented. iOS 18.1+.
  final bool sheet;

  /// Whether images can be generated without any UI. iOS 18.4+.
  final bool creator;

  /// Whether anything at all is usable.
  bool get isAvailable => sheet || creator;

  @override
  String toString() =>
      'ImageGenerationAvailability($status, sheet: $sheet, creator: $creator)';
}
