import 'package:apple_intelligence/apple_intelligence.dart';
import 'package:apple_intelligence/src/bridge.dart';
import 'package:apple_intelligence/src/exceptions.dart' show exceptionFor;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal PNG header, so byte assertions mean something.
Uint8List fakePng(int size) {
  final Uint8List bytes = Uint8List(size);
  bytes.setRange(0, 8, <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  return bytes;
}

void main() {
  _nativeTextTests();
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final List<MethodCall> calls = <MethodCall>[];
  int startedId = -1;

  void onMethod(Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(Bridge.method, (MethodCall call) {
      calls.add(call);
      if (call.method == 'creator.start') {
        startedId = (call.arguments as Map<Object?, Object?>)['id']! as int;
      }
      return handler(call);
    });
  }

  void onEvents(void Function(MockStreamHandlerEventSink sink, int id) emit) {
    messenger.setMockStreamHandler(
      Bridge.events,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink sink) {
          // Deferred: emitting inside onListen races the subscription that the
          // stream under test has not finished setting up yet.
          // Long enough for creator.start to have been invoked, so the
          // emitted events carry the id the package is actually filtering on.
          Future<void>.delayed(
            const Duration(milliseconds: 5),
            () => emit(sink, startedId),
          );
        },
      ),
    );
  }

  setUp(() {
    calls.clear();
    startedId = -1;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(Bridge.method, null);
    messenger.setMockStreamHandler(Bridge.events, null);
  });

  group('concepts', () {
    test('a named concept is not an extraction request', () {
      const ImageConcept c = ImageConcept.text('a fox');
      expect(c.toMap(), <String, Object?>{'text': 'a fox', 'extract': false});
    });

    test('extraction carries its optional title', () {
      const ImageConcept c = ImageConcept.extractedFrom(
        'long prose',
        title: 'Notes',
      );
      expect(c.toMap(), <String, Object?>{
        'text': 'long prose',
        'title': 'Notes',
        'extract': true,
      });
    });

    test('styles use their own names on the wire', () {
      expect(ImageStyle.animation.wireName, 'animation');
      expect(ImageStyle.illustration.wireName, 'illustration');
      expect(ImageStyle.sketch.wireName, 'sketch');
    });
  });

  group('availability', () {
    test('the sheet and streaming are reported separately', () async {
      onMethod(
        (_) async => <String, Object?>{
          'status': 'available',
          'sheet': true,
          'creator': false,
        },
      );
      final ImageGenerationAvailability a = await ImageCreator.availability();
      expect(a.status, ImageGenerationStatus.available);
      expect(a.sheet, isTrue);
      // 18.1 has the sheet, 18.4 adds streaming. A device can have one only.
      expect(a.creator, isFalse);
      expect(a.isAvailable, isTrue);
    });

    test('an old OS is distinguishable from a disabled one', () async {
      onMethod((_) async => <String, Object?>{'status': 'osTooOld'});
      final ImageGenerationAvailability a = await ImageCreator.availability();
      expect(a.status, ImageGenerationStatus.osTooOld);
      expect(a.isAvailable, isFalse);
    });

    test('an unknown status is treated as unavailable, not a crash', () async {
      onMethod((_) async => <String, Object?>{'status': 'something new'});
      final ImageGenerationAvailability a = await ImageCreator.availability();
      expect(a.status, ImageGenerationStatus.unavailable);
    });
  });

  group('streaming generation', () {
    test('images arrive in order and the stream closes', () async {
      onMethod((_) async => null);
      onEvents((MockStreamHandlerEventSink sink, int id) {
        for (int i = 0; i < 3; i++) {
          sink.success(<Object?, Object?>{
            'id': id,
            'type': 'image',
            'index': i,
            'bytes': fakePng(64 + i),
          });
        }
        sink.success(<Object?, Object?>{'id': id, 'type': 'done', 'count': 3});
      });

      final List<GeneratedImage> got = await ImageCreator.generate(
        concepts: <ImageConcept>[const ImageConcept.text('a fox')],
        limit: 3,
      ).toList();

      expect(got.map((GeneratedImage g) => g.index), <int>[0, 1, 2]);
      expect(got.first.bytes.length, 64);
      final MethodCall start = calls.firstWhere(
        (MethodCall c) => c.method == 'creator.start',
      );
      expect((start.arguments as Map<Object?, Object?>)['limit'], 3);
    });

    test('another run\'s traffic is ignored', () async {
      onMethod((_) async => null);
      onEvents((MockStreamHandlerEventSink sink, int id) {
        // Same event channel, different generation. Must not leak across.
        sink.success(<Object?, Object?>{
          'id': id + 1000,
          'type': 'image',
          'index': 0,
          'bytes': fakePng(10),
        });
        sink.success(<Object?, Object?>{'id': id + 1000, 'type': 'done'});
        sink.success(<Object?, Object?>{
          'id': id,
          'type': 'image',
          'index': 0,
          'bytes': fakePng(20),
        });
        sink.success(<Object?, Object?>{'id': id, 'type': 'done'});
      });

      final List<GeneratedImage> got = await ImageCreator.generate(
        concepts: <ImageConcept>[const ImageConcept.text('a fox')],
      ).toList();
      expect(got, hasLength(1));
      expect(got.single.bytes.length, 20);
    });

    test('a refusal surfaces as a typed exception', () async {
      onMethod((_) async => null);
      onEvents((MockStreamHandlerEventSink sink, int id) {
        sink.success(<Object?, Object?>{
          'id': id,
          'type': 'error',
          'code': 'unsupportedLanguage',
          'message': 'That language is not supported.',
        });
      });

      await expectLater(
        ImageCreator.generate(
          concepts: <ImageConcept>[const ImageConcept.text('狐')],
        ),
        emitsError(
          isA<GenerationRefusedException>().having(
            (GenerationRefusedException e) => e.reason,
            'reason',
            GenerationRefusal.unsupportedLanguage,
          ),
        ),
      );
    });

    test('a start failure surfaces as a typed exception', () async {
      onMethod((MethodCall call) async {
        if (call.method == 'creator.start') {
          throw PlatformException(code: 'osTooOld', message: 'Needs 18.4.');
        }
        return null;
      });
      onEvents((MockStreamHandlerEventSink sink, int id) {});

      await expectLater(
        ImageCreator.generate(
          concepts: <ImageConcept>[const ImageConcept.text('a fox')],
        ),
        emitsError(isA<OsTooOldException>()),
      );
    });

    test('cancelling the subscription cancels the device work', () async {
      onMethod((_) async => null);
      onEvents((MockStreamHandlerEventSink sink, int id) {
        sink.success(<Object?, Object?>{
          'id': id,
          'type': 'image',
          'index': 0,
          'bytes': fakePng(32),
        });
      });

      final Stream<GeneratedImage> stream = ImageCreator.generate(
        concepts: <ImageConcept>[const ImageConcept.text('a fox')],
        limit: 10,
      );
      await stream.first; // take one, then walk away
      await Future<void>.delayed(Duration.zero);
      expect(
        calls.map((MethodCall c) => c.method),
        contains('creator.cancel'),
        reason: 'a cancelled subscription must stop the work on the device',
      );
    });

    test('rejects impossible requests before touching the platform', () {
      expect(
        () => ImageCreator.generate(concepts: const <ImageConcept>[]),
        throwsAssertionError,
      );
      expect(
        () => ImageCreator.generate(
          concepts: <ImageConcept>[const ImageConcept.text('a fox')],
          limit: 0,
        ),
        throwsAssertionError,
      );
    });
  });

  group('the sheet', () {
    test('returns the written path', () async {
      onMethod((_) async => '/tmp/generated.png');
      final String? path = await ImagePlaygroundSheet.present(
        concepts: <ImageConcept>[const ImageConcept.text('a fox')],
        style: ImageStyle.sketch,
      );
      expect(path, '/tmp/generated.png');
      final Map<Object?, Object?> args =
          calls.single.arguments as Map<Object?, Object?>;
      expect(args['style'], 'sketch');
      expect(args['concepts'], hasLength(1));
    });

    test('a cancelled sheet is null, not an error', () async {
      onMethod((_) async => null);
      expect(await ImagePlaygroundSheet.present(), isNull);
    });

    test('platform errors become typed exceptions', () async {
      onMethod((_) async {
        throw PlatformException(code: 'unavailable', message: 'Turned off.');
      });
      await expectLater(
        ImagePlaygroundSheet.present(),
        throwsA(isA<GenerationUnavailableException>()),
      );
    });

    test('only sends a source image when there is one', () async {
      onMethod((_) async => null);
      await ImagePlaygroundSheet.present();
      expect(
        (calls.single.arguments as Map<Object?, Object?>).containsKey(
          'sourceImagePath',
        ),
        isFalse,
      );
    });
  });

  group('error mapping', () {
    test('every platform code maps to a distinguishable exception', () {
      expect(exceptionFor('osTooOld', 'x'), isA<OsTooOldException>());
      expect(
        exceptionFor('unavailable', 'x'),
        isA<GenerationUnavailableException>(),
      );
      expect(
        exceptionFor('notSupported', 'x'),
        isA<GenerationUnavailableException>(),
      );
      for (final (String code, GenerationRefusal reason)
          in <(String, GenerationRefusal)>[
            ('unsupportedLanguage', GenerationRefusal.unsupportedLanguage),
            ('unsupportedInputImage', GenerationRefusal.unsupportedInputImage),
            ('faceTooSmall', GenerationRefusal.faceTooSmall),
            (
              'conceptsRequirePersonIdentity',
              GenerationRefusal.conceptsRequirePersonIdentity,
            ),
            ('backgroundForbidden', GenerationRefusal.backgroundForbidden),
          ]) {
        final AppleIntelligenceException e = exceptionFor(code, 'x');
        expect(e, isA<GenerationRefusedException>(), reason: code);
        expect((e as GenerationRefusedException).reason, reason);
      }
      // Anything unrecognised must still be one of ours, not a raw throw.
      expect(
        exceptionFor('brand new code', 'x'),
        isA<GenerationFailedException>(),
      );
    });
  });
}

void _nativeTextTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const MethodChannel fake = MethodChannel(
    'dev.shakib/apple_intelligence/text/7',
  );
  final List<MethodCall> calls = <MethodCall>[];
  String stored = 'hello';

  setUp(() {
    calls.clear();
    stored = 'hello';
    messenger.setMockMethodCallHandler(fake, (MethodCall call) async {
      calls.add(call);
      switch (call.method) {
        case 'getText':
          return stored;
        case 'setText':
          stored = (call.arguments as Map<Object?, Object?>)['text']! as String;
          return null;
        case 'capabilities':
          return <Object?, Object?>{'writingTools': true, 'genmoji': true};
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(fake, null));

  group('native text controller', () {
    test('says so when it is not attached', () {
      final NativeTextController c = NativeTextController();
      expect(c.isAttached, isFalse);
      expect(c.getText, throwsStateError);
      expect(() => c.setText('x'), throwsStateError);
      expect(c.capabilities, throwsStateError);
    });

    test('reads and writes through the attached view', () async {
      final NativeTextController c = NativeTextController()..attach(fake);
      expect(c.isAttached, isTrue);
      expect(await c.getText(), 'hello');
      await c.setText('rewritten');
      expect(await c.getText(), 'rewritten');
      expect(
        calls.map((MethodCall m) => m.method),
        containsAll(<String>['getText', 'setText']),
      );
    });

    test(
      'reports what the live view was granted, not what the OS implies',
      () async {
        final NativeTextController c = NativeTextController()..attach(fake);
        final TextCapabilities caps = await c.capabilities();
        expect(caps.writingTools, isTrue);
        expect(caps.genmoji, isTrue);
        expect(caps.toString(), contains('writingTools: true'));
      },
    );

    test('detaching stops it answering', () {
      final NativeTextController c = NativeTextController()..attach(fake);
      c.detach();
      expect(c.isAttached, isFalse);
      expect(c.getText, throwsStateError);
    });
  });

  group('the widget', () {
    testWidgets('renders the fallback where there is no native view to host', (
      WidgetTester tester,
    ) async {
      // The test binding reports the host platform, so this exercises whichever
      // branch this machine is: a real view on macOS, the fallback elsewhere.
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: AppleIntelligenceTextField(
            fallback: Text('not supported here'),
          ),
        ),
      );
      if (!AppleIntelligenceTextField.isSupported) {
        expect(find.text('not supported here'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    test('rejects an impossible font size', () {
      expect(
        () => AppleIntelligenceTextField(fontSize: 0),
        throwsAssertionError,
      );
    });
  });
}
