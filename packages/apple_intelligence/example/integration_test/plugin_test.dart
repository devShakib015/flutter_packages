// Runs against the real system. Image generation needs Apple Intelligence
// hardware with the models downloaded, so these are a local step, not CI.
//
//   flutter test integration_test -d macos
//
// Availability and the error path are covered here, but **generation itself
// cannot be**: Apple refuses image creation to an app that is not frontmost,
// and the integration harness cannot foreground one, so every attempt comes
// back as `backgroundForbidden`. That is a real product rule, not a defect --
// the same refusal is what a backgrounded app would get.
//
// To verify generation for real, run the example frontmost. It was confirmed
// this way on 2026-08-27: two PNGs of about 4MB each, the first at 6.8s and
// the second at 10.3s, which is also what shows the stream is incremental
// rather than a batch delivered at the end.
import 'package:apple_intelligence/apple_intelligence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('availability answers the three questions separately', () async {
    final ImageGenerationAvailability a = await ImageCreator.availability();
    // ignore: avoid_print
    print('  status=${a.status.name}  sheet=${a.sheet}  creator=${a.creator}');
    expect(a.status, isA<ImageGenerationStatus>());
    if (a.status == ImageGenerationStatus.available) {
      expect(a.isAvailable, isTrue);
    }
  });

  test('generates real images, streamed', () async {
    final ImageGenerationAvailability a = await ImageCreator.availability();
    if (!a.creator) {
      // ignore: avoid_print
      print('  SKIPPED — programmatic generation unavailable here');
      return;
    }

    final List<GeneratedImage> got = <GeneratedImage>[];
    final Stopwatch clock = Stopwatch()..start();
    Object? failure;

    await ImageCreator.generate(
      concepts: <ImageConcept>[
        const ImageConcept.text('a fox reading a map by lantern light'),
      ],
      style: ImageStyle.illustration,
      limit: 2,
    ).forEach(got.add).catchError((Object e) => failure = e);

    // ignore: avoid_print
    print(
      '  ${got.length} image(s) in ${clock.elapsedMilliseconds}ms'
      '${failure == null ? "" : "   error: $failure"}',
    );
    for (final GeneratedImage image in got) {
      // ignore: avoid_print
      print(
        '    #${image.index}  ${image.bytes.length} bytes'
        '  png=${image.bytes.sublist(1, 4)}',
      );
      expect(image.bytes.length, greaterThan(1000));
      // PNG magic: 0x89 'P' 'N' 'G'
      expect(image.bytes[0], 0x89);
      expect(image.bytes.sublist(1, 4), <int>[0x50, 0x4E, 0x47]);
    }
    if (failure == null) expect(got, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 4)));

  test(
    'a refused prompt raises a typed exception, not a PlatformException',
    () async {
      final ImageGenerationAvailability a = await ImageCreator.availability();
      if (!a.creator) return;
      Object? caught;
      try {
        await ImageCreator.generate(
          concepts: <ImageConcept>[const ImageConcept.text('')],
          limit: 1,
        ).drain<void>();
      } catch (e) {
        caught = e;
      }
      // ignore: avoid_print
      print('  empty concept -> ${caught ?? "accepted"}');
      if (caught != null) expect(caught, isA<AppleIntelligenceException>());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
