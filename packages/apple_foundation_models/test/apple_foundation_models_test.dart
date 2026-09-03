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
}
