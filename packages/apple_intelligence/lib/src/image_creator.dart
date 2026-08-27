import 'dart:async';

import 'package:flutter/services.dart';

import 'availability.dart';
import 'bridge.dart';
import 'concept.dart';
import 'exceptions.dart';

/// One image, as it arrives.
class GeneratedImage {
  /// Creates a generated image.
  const GeneratedImage({required this.bytes, required this.index});

  /// PNG data.
  final Uint8List bytes;

  /// Position in the run, starting at zero.
  final int index;

  @override
  String toString() => 'GeneratedImage(#$index, ${bytes.length} bytes)';
}

/// Generates images on device, with no UI at all.
///
/// Results arrive as a stream because the system produces them one at a time —
/// showing the first while the rest are still coming is the difference between
/// a responsive screen and a spinner. Cancelling the subscription cancels the
/// work on the device.
///
/// Needs iOS 18.4 or macOS 15.4; the sheet in [ImagePlaygroundSheet] goes back
/// further. Check [availability] rather than assuming.
class ImageCreator {
  const ImageCreator._();

  static int _nextId = 0;

  /// What this device can do.
  static Future<ImageGenerationAvailability> availability() async {
    final Map<Object?, Object?>? reply = await Bridge.method
        .invokeMethod<Map<Object?, Object?>>('availability');
    return ImageGenerationAvailability.fromMap(
      reply ?? const <Object?, Object?>{},
    );
  }

  /// Generates up to [limit] images for [concepts].
  ///
  /// The stream closes when the run finishes. Errors arrive as the typed
  /// exceptions in `exceptions.dart` rather than as [PlatformException], so a
  /// caller can tell "this device cannot" from "this prompt was refused".
  static Stream<GeneratedImage> generate({
    required List<ImageConcept> concepts,
    ImageStyle style = ImageStyle.animation,
    int limit = 1,
  }) {
    assert(concepts.isNotEmpty, 'at least one concept is required');
    assert(limit > 0, 'limit must be positive');

    final int id = _nextId++;
    late StreamController<GeneratedImage> controller;
    StreamSubscription<dynamic>? subscription;

    Future<void> stop() async {
      await subscription?.cancel();
      subscription = null;
      try {
        await Bridge.method.invokeMethod<void>(
          'creator.cancel',
          <String, Object?>{'id': id},
        );
      } on PlatformException {
        // The run had already finished; nothing to cancel.
      }
    }

    controller = StreamController<GeneratedImage>(
      onCancel: stop,
      onListen: () async {
        subscription = Bridge.events.receiveBroadcastStream().listen((
          dynamic event,
        ) {
          if (event is! Map) return;
          if (event['id'] != id) return; // Another run's traffic.
          switch (event['type']) {
            case 'image':
              controller.add(
                GeneratedImage(
                  bytes: event['bytes'] as Uint8List,
                  index: event['index'] as int,
                ),
              );
            case 'error':
              controller.addError(
                exceptionFor(
                  event['code'] as String? ?? 'creationFailed',
                  event['message'] as String? ?? 'Generation failed.',
                ),
              );
              controller.close();
            case 'done':
              controller.close();
          }
        }, onError: controller.addError);

        try {
          await Bridge.method.invokeMethod<void>(
            'creator.start',
            <String, Object?>{
              'id': id,
              'concepts': concepts.map((ImageConcept c) => c.toMap()).toList(),
              'style': style.wireName,
              'limit': limit,
            },
          );
        } on PlatformException catch (e) {
          controller.addError(exceptionFor(e.code, e.message ?? e.code));
          await controller.close();
        }
      },
    );
    return controller.stream;
  }
}
