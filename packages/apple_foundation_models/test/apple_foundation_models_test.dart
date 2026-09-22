import 'dart:async';
import 'dart:io';

import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Everything here runs without a model: schema translation, error mapping,
/// and the graceful-degradation path other platforms take.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'dev.shakib/apple_foundation_models',
  );

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  group('Schema', () {
    test('primitives carry their description', () {
      expect(Schema.string(description: 'a name').toJson(), <String, Object?>{
        'type': 'string',
        'description': 'a name',
      });
      expect(
          Schema.integer().toJson(),
          <String, Object?>{
            'type': 'integer',
          },
          reason: 'null fields are stripped rather than sent as null');
    });

    test('objects mark optional properties', () {
      final Map<String, Object?> json = Schema.object(
        name: 'Person',
        <String, Schema>{'name': Schema.string(), 'age': Schema.integer()},
        optional: <String>{'age'},
      ).toJson();

      expect(json['name'], 'Person');
      final List<Object?> props = json['properties']! as List<Object?>;
      expect(props, hasLength(2));
      expect((props[0]! as Map<String, Object?>)['isOptional'], isFalse);
      expect((props[1]! as Map<String, Object?>)['isOptional'], isTrue);
    });

    test('arrays carry their bounds', () {
      final Map<String, Object?> json = Schema.array(
        Schema.string(),
        maxItems: 3,
      ).toJson();
      expect(json['type'], 'array');
      expect(json['maxItems'], 3);
      expect(json.containsKey('minItems'), isFalse);
    });

    test('rejects shapes the model could not satisfy', () {
      expect(
        () => Schema.object(const <String, Schema>{}),
        throwsAssertionError,
        reason: 'an object with no properties has nothing to generate',
      );
      expect(() => Schema.oneOf(const <String>[]), throwsAssertionError);
      expect(
        () => Schema.array(Schema.string(), minItems: 5, maxItems: 2),
        throwsAssertionError,
      );
      expect(
        () => Schema.object(
          <String, Schema>{'a': Schema.string()},
          optional: <String>{'typo'},
        ),
        throwsAssertionError,
        reason: 'an optional name that matches nothing is a silent bug',
      );
    });
  });

  group('guides', () {
    test('bounds ride along on the wire', () {
      expect(Schema.integer(min: 1, max: 5).toJson(), <String, Object?>{
        'type': 'integer',
        'minimum': 1,
        'maximum': 5,
      });
      expect(Schema.number(min: 0).toJson()['minimum'], 0.0);
      expect(Schema.number(max: 1).toJson().containsKey('minimum'), isFalse);
      expect(
        Schema.string(pattern: r'^[A-Z]{3}$').toJson()['pattern'],
        r'^[A-Z]{3}$',
      );
    });

    test('exactItems collapses to equal bounds', () {
      final Map<String, Object?> json = Schema.array(
        Schema.string(),
        exactItems: 3,
      ).toJson();
      expect(json['minItems'], 3);
      expect(json['maxItems'], 3);
    });

    test('rejects contradictory bounds', () {
      expect(() => Schema.integer(min: 5, max: 1), throwsAssertionError);
      expect(() => Schema.number(min: 1, max: 0), throwsAssertionError);
      expect(
        () => Schema.array(Schema.string(), exactItems: 3, maxItems: 5),
        throwsAssertionError,
        reason: 'an exact length and a range together is a contradiction',
      );
    });
  });

  group('deltas', () {
    test('subtracts each cumulative snapshot from the last', () async {
      final List<String> out = await Stream<String>.fromIterable(<String>[
        'He',
        'Hello',
        'Hello there',
      ]).deltas().toList();
      expect(out, <String>['He', 'llo', ' there']);
      expect(out.join(), 'Hello there');
    });

    test('emits a non-extending snapshot whole', () async {
      // The model occasionally revises rather than extends; concatenation must
      // still end up correct rather than interleaving two drafts.
      final List<String> out = await Stream<String>.fromIterable(<String>[
        'Hello',
        'Goodbye',
      ]).deltas().toList();
      expect(out, <String>['Hello', 'Goodbye']);
    });

    test('skips repeats and handles an empty stream', () async {
      expect(
        await Stream<String>.fromIterable(<String>['Hi', 'Hi'])
            .deltas()
            .toList(),
        <String>['Hi'],
      );
      expect(await const Stream<String>.empty().deltas().toList(), isEmpty);
    });
  });

  group('use cases', () {
    test('every case has a wire name', () {
      for (final ModelUseCase useCase in ModelUseCase.values) {
        expect(useCase.wireName, isNotEmpty);
      }
    });
  });

  group('GenerationOptions', () {
    test('omits unset fields entirely', () {
      expect(const GenerationOptions().toJson(), isEmpty);
    });

    test('serialises each sampling mode', () {
      expect(
        const GenerationOptions(sampling: SamplingMode.greedy()).toJson(),
        <String, Object?>{
          'sampling': <String, Object?>{'mode': 'greedy'},
        },
      );
      expect(
        const GenerationOptions(sampling: SamplingMode.topK(40, seed: 7))
            .toJson()['sampling'],
        <String, Object?>{'mode': 'topK', 'k': 40, 'seed': 7},
      );
      expect(
        const GenerationOptions(sampling: SamplingMode.topP(0.9))
            .toJson()['sampling'],
        <String, Object?>{'mode': 'topP', 'threshold': 0.9},
      );
    });

    test('rejects impossible values', () {
      expect(() => GenerationOptions(temperature: -1), throwsAssertionError);
      expect(
        () => GenerationOptions(maximumResponseTokens: 0),
        throwsAssertionError,
      );
    });
  });

  group('availability', () {
    test('reports the reason and whether waiting could help', () {
      const ModelUnavailable notReady = ModelUnavailable(
        ModelUnavailableReason.modelNotReady,
      );
      expect(notReady.isAvailable, isFalse);
      expect(notReady.reason.isTransient, isTrue);
      expect(notReady.remedy, isNotNull);

      const ModelUnavailable ineligible = ModelUnavailable(
        ModelUnavailableReason.deviceNotEligible,
      );
      expect(ineligible.reason.isTransient, isFalse);
      expect(
        ineligible.remedy,
        isNull,
        reason: 'nothing the user does will fix incapable hardware',
      );
    });

    test('every reason explains itself', () {
      for (final ModelUnavailableReason reason
          in ModelUnavailableReason.values) {
        expect(reason.explanation, isNotEmpty);
      }
    });

    test('maps a platform reason onto the enum', () async {
      mock(
        (MethodCall call) async => <String, Object?>{
          'available': false,
          'reason': 'modelNotReady',
        },
      );
      expect(
        await AppleFoundationModels.availability(),
        const ModelUnavailable(ModelUnavailableReason.modelNotReady),
      );
    });

    test('an unrecognised reason degrades to unknown', () async {
      mock(
        (MethodCall call) async => <String, Object?>{
          'available': false,
          'reason': 'from-the-future',
        },
      );
      expect(
        await AppleFoundationModels.availability(),
        const ModelUnavailable(ModelUnavailableReason.unknown),
      );
    });
  });

  group('graceful degradation', () {
    test('a platform without the plugin reports unsupportedPlatform', () async {
      // No mock installed at all, which is what Android and web see.
      expect(
        await AppleFoundationModels.availability(),
        const ModelUnavailable(ModelUnavailableReason.unsupportedPlatform),
      );
      expect(await AppleFoundationModels.isAvailable, isFalse);
    });

    test('creating a session there throws rather than hanging', () async {
      await expectLater(
        LanguageModelSession.create(),
        throwsA(
          isA<ModelUnavailableException>().having(
            (ModelUnavailableException e) => e.reason,
            'reason',
            ModelUnavailableReason.unsupportedPlatform,
          ),
        ),
      );
    });
  });

  group('error translation', () {
    Future<void> expectMapped(String code, Matcher matcher) async {
      mock((MethodCall call) async {
        if (call.method == 'session.create') return 1;
        throw PlatformException(code: code, message: 'boom');
      });
      final LanguageModelSession session = await LanguageModelSession.create();
      await expectLater(session.respond('hi'), throwsA(matcher));
    }

    test(
      'context window overflow',
      () => expectMapped(
        'exceededContextWindowSize',
        isA<ContextWindowExceededException>(),
      ),
    );
    test(
      'guardrail violation',
      () => expectMapped(
        'guardrailViolation',
        isA<GuardrailViolationException>(),
      ),
    );
    test('refusal', () => expectMapped('refusal', isA<RefusalException>()));
    test(
      'concurrent requests',
      () =>
          expectMapped('concurrentRequests', isA<ConcurrentRequestException>()),
    );
    test(
      'decoding failure',
      () => expectMapped('decodingFailure', isA<DecodingFailureException>()),
    );
    test(
      'unknown codes still arrive typed',
      () => expectMapped(
        'something-new',
        isA<FoundationModelsPlatformException>(),
      ),
    );
  });

  group('session', () {
    test('rejects duplicate tool names before reaching the platform', () async {
      mock((MethodCall call) async => 1);
      LanguageModelTool tool(String name) => LanguageModelTool(
            name: name,
            description: 'x',
            parameters: Schema.object(<String, Schema>{'a': Schema.string()}),
            handler: (_) => 'ok',
          );
      await expectLater(
        LanguageModelSession.create(
          tools: <LanguageModelTool>[tool('dup'), tool('dup')],
        ),
        throwsArgumentError,
      );
    });

    test('malformed model output surfaces as DecodingFailure', () async {
      mock((MethodCall call) async {
        if (call.method == 'session.create') return 1;
        return 'not json at all';
      });
      final LanguageModelSession session = await LanguageModelSession.create();
      await expectLater(
        session.respondAs(
          'hi',
          schema: Schema.object(<String, Schema>{'a': Schema.string()}),
        ),
        throwsA(isA<DecodingFailureException>()),
      );
    });
  });

  group('transcript', () {
    // Roles cross the channel as strings, written in Swift and read here. One
    // the plugin sends that Dart does not know arrives as unknown without a
    // word, which is how reasoning went missing — so hold both sides to it.
    test('every role the plugin sends has a TranscriptRole', () {
      final String swift = File(
        'darwin/apple_foundation_models/Sources/apple_foundation_models/'
        'AppleFoundationModelsPlugin.swift',
      ).readAsStringSync();
      final Set<String> sent = RegExp(r'"role": "(\w+)"')
          .allMatches(swift)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();
      // A pattern that matched nothing would pass everything below.
      expect(sent, containsAll(<String>['prompt', 'response', 'reasoning']));
      for (final String role in sent.difference(<String>{'unknown'})) {
        final TranscriptEntry entry = TranscriptEntry.fromJson(
          <String, Object?>{'role': role, 'text': 'x'},
        );
        expect(entry.role, isNot(TranscriptRole.unknown), reason: role);
      }
    });

    test('a role this version does not know still reads as unknown', () {
      final TranscriptEntry entry = TranscriptEntry.fromJson(
        <String, Object?>{'role': 'telepathy', 'text': 'hm'},
      );
      expect(entry.role, TranscriptRole.unknown);
      expect(entry.text, 'hm');
    });
  });

  group('images', () {
    final Uint8List png = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]);

    // Records every call and answers the ones a request needs.
    List<MethodCall> record() {
      final List<MethodCall> calls = <MethodCall>[];
      mock((MethodCall call) async {
        calls.add(call);
        return switch (call.method) {
          'session.create' => 1,
          'session.respond' => 'ok',
          'session.respondAs' => '{}',
          _ => null,
        };
      });
      return calls;
    }

    Object? sentImages(List<MethodCall> calls, String method) =>
        (calls.lastWhere((MethodCall c) => c.method == method).arguments
            as Map<Object?, Object?>)['images'];

    test('ride along with a prompt: bytes, files and labels', () async {
      final List<MethodCall> calls = record();
      final LanguageModelSession session = await LanguageModelSession.create();
      await session.respond(
        'What is this?',
        images: <PromptImage>[
          PromptImage.bytes(png, label: 'photo'),
          const PromptImage.file('/tmp/receipt.jpg'),
        ],
      );
      expect(sentImages(calls, 'session.respond'), <Map<String, Object?>>[
        <String, Object?>{'bytes': png, 'label': 'photo'},
        <String, Object?>{'path': '/tmp/receipt.jpg'},
      ]);
    });

    test('a text-only request is sent exactly as before', () async {
      final List<MethodCall> calls = record();
      final LanguageModelSession session = await LanguageModelSession.create();
      await session.respond('hi');
      final Map<Object?, Object?> args = calls.last.arguments as Map;
      expect(args.containsKey('images'), isFalse);
    });

    test('every request method carries them, streams included', () async {
      final List<MethodCall> calls = record();
      const EventChannel events = EventChannel(
        'dev.shakib/apple_foundation_models/events',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        events,
        MockStreamHandler.inline(onListen: (Object? _, __) {}),
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(events, null),
      );

      final LanguageModelSession session = await LanguageModelSession.create();
      const List<PromptImage> images = <PromptImage>[
        PromptImage.file('/tmp/a.png'),
      ];
      final Schema schema = Schema.object(<String, Schema>{
        'a': Schema.string(),
      });
      await session.respondAs('x', schema: schema, images: images);
      final StreamSubscription<String> plain =
          session.stream('x', images: images).listen((_) {});
      final StreamSubscription<Map<String, Object?>> shaped =
          session.streamAs('x', schema: schema, images: images).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await plain.cancel();
      await shaped.cancel();

      for (final String method in <String>[
        'session.respondAs',
        'session.stream',
        'session.streamAs',
      ]) {
        expect(
          sentImages(calls, method),
          <Map<String, Object?>>[
            <String, Object?>{'path': '/tmp/a.png'},
          ],
          reason: method,
        );
      }
    });

    test('an image that cannot decode is refused before anything is sent',
        () async {
      final List<MethodCall> calls = record();
      final LanguageModelSession session = await LanguageModelSession.create();
      expect(
        () => session.respond(
          'x',
          images: <PromptImage>[PromptImage.bytes(Uint8List(0))],
        ),
        throwsArgumentError,
      );
      expect(
        () => session.stream(
          'x',
          images: <PromptImage>[const PromptImage.file('')],
        ),
        throwsArgumentError,
      );
      expect(calls.map((MethodCall c) => c.method), <String>['session.create']);
    });

    test('supportsImages reports what the platform says', () async {
      mock(
        (MethodCall call) async =>
            call.method == 'supportsImages' ? true : null,
      );
      expect(await AppleFoundationModels.supportsImages(), isTrue);
    });

    test('supportsImages is false where the plugin is missing', () async {
      // No mock at all, which is what Android and the web see.
      expect(await AppleFoundationModels.supportsImages(), isFalse);
    });

    test('a request the platform cannot serve says so', () async {
      mock((MethodCall call) async {
        if (call.method == 'session.create') return 1;
        throw PlatformException(
          code: 'unsupportedCapability',
          message: 'Images in a prompt need iOS 27 or macOS 27.',
        );
      });
      final LanguageModelSession session = await LanguageModelSession.create();
      await expectLater(
        session.respond('x', images: <PromptImage>[PromptImage.bytes(png)]),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
    });

    test('an unreadable image is named by its index', () async {
      mock((MethodCall call) async {
        if (call.method == 'session.create') return 1;
        throw PlatformException(
          code: 'invalidImage',
          message: 'Image 1 could not be read.',
          details: <String, Object?>{'index': '1'},
        );
      });
      final LanguageModelSession session = await LanguageModelSession.create();
      await expectLater(
        session.respond('x', images: <PromptImage>[PromptImage.bytes(png)]),
        throwsA(
          isA<InvalidImageException>()
              .having((InvalidImageException e) => e.index, 'index', 1),
        ),
      );
    });
  });
}
