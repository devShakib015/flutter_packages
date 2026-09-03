import 'package:flutter/services.dart';

import 'bridge.dart';
import 'concept.dart';
import 'exceptions.dart';

/// Apple's own image generation UI, presented over your app.
///
/// The user picks and refines the image; you get back the file it wrote. Use
/// this when you want the system experience and the system's own safety
/// affordances. Use `ImageCreator` when you want images without a modal.
class ImagePlaygroundSheet {
  const ImagePlaygroundSheet._();

  /// Presents the sheet and completes with the path of the generated image,
  /// or null if the user cancelled.
  ///
  /// [concepts] seed the sheet; the user can change them. [style] preselects a
  /// look, and [allowedStyles] restricts which ones are offered at all —
  /// useful when only one register suits your app. [sourceImagePath] starts
  /// from an existing picture rather than from nothing.
  ///
  /// Throws [OsTooOldException] below iOS 18.1 or macOS 15.1, and
  /// [GenerationUnavailableException] where Apple Intelligence is off.
  static Future<String?> present({
    List<ImageConcept> concepts = const <ImageConcept>[],
    ImageStyle? style,
    List<ImageStyle>? allowedStyles,
    String? sourceImagePath,
  }) async {
    try {
      return await Bridge.method.invokeMethod<String>(
        'sheet.present',
        <String, Object?>{
          'concepts': concepts.map((ImageConcept c) => c.toMap()).toList(),
          if (style != null) 'style': style.wireName,
          if (allowedStyles != null)
            'allowedStyles':
                allowedStyles.map((ImageStyle s) => s.wireName).toList(),
          if (sourceImagePath != null) 'sourceImagePath': sourceImagePath,
        },
      );
    } on PlatformException catch (e) {
      throw exceptionFor(e.code, e.message ?? e.code);
    }
  }
}
