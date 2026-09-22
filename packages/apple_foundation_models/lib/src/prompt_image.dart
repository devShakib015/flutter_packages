import 'package:flutter/foundation.dart';

/// An image for the model to look at along with a prompt.
///
/// Needs iOS 27 or macOS 27, an app built with Xcode 27 or later, and a model
/// that can see; `AppleFoundationModels.supportsImages` answers all three.
/// Where images are not supported, a request carrying one throws
/// `UnsupportedCapabilityException` rather than quietly leaving it out.
///
/// ```dart
/// final answer = await session.respond(
///   'What is the total on this receipt?',
///   images: [PromptImage.file(photo.path, label: 'receipt')],
/// );
/// ```
@immutable
final class PromptImage {
  /// Encoded image data: PNG, JPEG, HEIC, or anything else Core Image
  /// decodes.
  const PromptImage.bytes(Uint8List this.bytes, {this.label}) : path = null;

  /// An image file, read natively, so its bytes never cross the platform
  /// channel.
  const PromptImage.file(String this.path, {this.label}) : bytes = null;

  /// The encoded image, when made with [PromptImage.bytes].
  final Uint8List? bytes;

  /// The file, when made with [PromptImage.file].
  final String? path;

  /// A name for the image. The model can refer to it — useful when there are
  /// several — and the transcript shows it as `[image: label]`.
  final String? label;

  /// The image as it crosses the platform channel.
  Map<String, Object?> toJson() => <String, Object?>{
        if (bytes != null) 'bytes': bytes,
        if (path != null) 'path': path,
        if (label != null) 'label': label,
      };

  @override
  String toString() => bytes != null
      ? 'PromptImage.bytes(${bytes!.length} bytes'
          '${label == null ? '' : ', label: $label'})'
      : 'PromptImage.file($path${label == null ? '' : ', label: $label'})';
}
