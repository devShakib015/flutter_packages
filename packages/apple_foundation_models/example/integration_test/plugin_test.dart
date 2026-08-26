import 'dart:async';

import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Runs against the real on-device model, so assertions are structural rather
/// than about wording — the same prompt does not produce the same sentence
/// twice, and testing for content would make this suite lie.
///
///   flutter test integration_test/plugin_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LanguageModelSession session;

  setUpAll(() async {
    final ModelAvailability availability =
        await AppleFoundationModels.availability();
    if (availability is ModelUnavailable) {
      fail(
        'Model unavailable (${availability.reason.name}). '
        '${availability.explanation} ${availability.remedy ?? ''}',
      );
    }
  });

  setUp(() async {
    session = await LanguageModelSession.create(
      instructions: 'You are terse. Answer in as few words as possible.',
    );
  });

  tearDown(() async => session.dispose());

  testWidgets('availability reports available', (_) async {
    expect(await AppleFoundationModels.availability(), const ModelAvailable());
    expect(await AppleFoundationModels.isAvailable, isTrue);
  });

  testWidgets('respond returns text', (_) async {
    final String reply = await session.respond('Name one primary colour.');
    expect(reply.trim(), isNotEmpty);
  });

  testWidgets('respondAs is constrained by the schema', (_) async {
    final Schema schema = Schema.object(
      name: 'Triage',
      <String, Schema>{
        'priority': Schema.oneOf(<String>['low', 'medium', 'high']),
        'summary': Schema.string(description: 'one short line'),
        'tags': Schema.array(Schema.string(), maxItems: 3),
        'hours': Schema.integer(),
      },
      optional: <String>{'hours'},
    );

    final Map<String, Object?> result = await session.respondAs(
      'Triage this: the login button does nothing on iPad.',
      schema: schema,
      options: GenerationOptions.deterministic,
    );

    expect(
      result['priority'],
      isIn(<String>['low', 'medium', 'high']),
      reason: 'an enum the model structurally cannot escape',
    );
    expect(result['summary'], isA<String>());
    expect(result['tags'], isA<List<Object?>>());
    expect((result['tags']! as List<Object?>).length, lessThanOrEqualTo(3));
  });

  testWidgets('stream emits cumulative snapshots, not deltas', (_) async {
    final List<String> snapshots = await session
        .stream('Count to five in words.')
        .toList();

    expect(snapshots, isNotEmpty);
    expect(snapshots.last.trim(), isNotEmpty);
    for (int i = 1; i < snapshots.length; i++) {
      expect(
        snapshots[i].length,
        greaterThanOrEqualTo(snapshots[i - 1].length),
        reason: 'each event must contain the previous one',
      );
    }
  });

  testWidgets('streamAs fills a schema progressively', (_) async {
    final Schema schema = Schema.object(<String, Schema>{
      'title': Schema.string(),
      'steps': Schema.array(Schema.string(), maxItems: 3),
    });

    final List<Map<String, Object?>> snapshots = await session
        .streamAs('How to boil an egg.', schema: schema)
        .toList();

    expect(snapshots, isNotEmpty);
    expect(snapshots.last['title'], isA<String>());
    expect(snapshots.last['steps'], isA<List<Object?>>());
  });

  testWidgets('the model calls a Dart tool and uses the result', (_) async {
    Map<String, Object?>? received;

    final LanguageModelSession tooled = await LanguageModelSession.create(
      instructions: 'Use the provided tools instead of guessing.',
      tools: <LanguageModelTool>[
        LanguageModelTool(
          name: 'getWeather',
          description:
              'Current weather for a city. Always call this rather '
              'than guessing the weather.',
          parameters: Schema.object(<String, Schema>{
            'city': Schema.string(description: 'city name'),
          }),
          handler: (Map<String, Object?> args) {
            received = args;
            return '18 degrees Celsius and raining';
          },
        ),
      ],
    );
    addTearDown(tooled.dispose);

    final String reply = await tooled.respond(
      'What is the weather in Dhaka right now?',
    );

    expect(received, isNotNull, reason: 'the tool should have been invoked');
    expect(received!['city'], isA<String>());
    expect(reply.trim(), isNotEmpty);
  });

  testWidgets('a tool that throws surfaces as ToolCallException', (_) async {
    final LanguageModelSession tooled = await LanguageModelSession.create(
      instructions: 'Always use the failing tool when asked the time.',
      tools: <LanguageModelTool>[
        LanguageModelTool(
          name: 'getTime',
          description:
              'The current time. Always call this when asked the time.',
          parameters: Schema.object(<String, Schema>{
            'zone': Schema.string(description: 'timezone name'),
          }),
          handler: (_) => throw StateError('clock unavailable'),
        ),
      ],
    );
    addTearDown(tooled.dispose);

    await expectLater(
      tooled.respond('What time is it in Dhaka?'),
      throwsA(isA<FoundationModelsException>()),
    );
  });

  testWidgets('prewarm and transcript work on a live session', (_) async {
    await session.prewarm();
    expect(await session.isResponding, isFalse);

    await session.respond('Say hello.');
    final List<TranscriptEntry> entries = await session.transcript();

    expect(entries, isNotEmpty);
    expect(
      entries.map((TranscriptEntry e) => e.role),
      contains(TranscriptRole.response),
    );
    expect(
      entries.every((TranscriptEntry e) => e.role != TranscriptRole.unknown),
      isTrue,
      reason: 'every transcript entry kind should be mapped',
    );
  });

  testWidgets('a second request while responding is rejected', (_) async {
    final Future<String> first = session.respond(
      'Write a detailed paragraph about the sea.',
    );
    await expectLater(
      session.respond('Hi'),
      throwsA(isA<ConcurrentRequestException>()),
      reason: 'a session handles one request at a time',
    );
    await first;
  });

  testWidgets('cancelling a stream frees the session', (_) async {
    final StreamSubscription<String> sub = session
        .stream('Write a very long essay about the ocean, in many paragraphs.')
        .listen((String _) {});

    await Future<void>.delayed(const Duration(milliseconds: 250));
    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(
      await session.isResponding,
      isFalse,
      reason: 'cancelling must release the session, not leave it wedged',
    );
    // The proof it is genuinely free: another request succeeds.
    expect((await session.respond('Say one word.')).trim(), isNotEmpty);
  });

  testWidgets('numeric guides bound what the model can emit', (_) async {
    // The point of a guide: without one, "rate 1 to 5" happily returns 47.
    final Schema schema = Schema.object(<String, Schema>{
      'severity': Schema.integer(min: 1, max: 5, description: 'severity'),
      'confidence': Schema.number(min: 0, max: 1, description: '0 to 1'),
    });

    for (final String prompt in <String>[
      'Rate the severity of: the app deletes user data on launch.',
      'Rate the severity of: a tooltip has a typo.',
    ]) {
      final Map<String, Object?> r = await session.respondAs(
        prompt,
        schema: schema,
        options: GenerationOptions.deterministic,
      );
      final num severity = r['severity']! as num;
      final num confidence = r['confidence']! as num;
      expect(severity, inInclusiveRange(1, 5), reason: 'for "\$prompt"');
      expect(confidence, inInclusiveRange(0, 1), reason: 'for "\$prompt"');
    }
  });

  testWidgets('an exact array length is honoured', (_) async {
    final Map<String, Object?> r = await session.respondAs(
      'Give exactly three colours.',
      schema: Schema.object(<String, Schema>{
        'colours': Schema.array(Schema.string(), exactItems: 3),
      }),
    );
    expect(r['colours'], hasLength(3));
  });

  testWidgets('the contentTagging model produces tags', (_) async {
    final LanguageModelSession tagger = await LanguageModelSession.create(
      useCase: ModelUseCase.contentTagging,
    );
    addTearDown(tagger.dispose);

    final Map<String, Object?> r = await tagger.respondAs(
      'A recipe for slow-cooked lamb with rosemary and garlic.',
      schema: Schema.object(<String, Schema>{
        'tags': Schema.array(Schema.string(), maxItems: 4),
      }),
    );
    expect(r['tags'], isA<List<Object?>>());
    expect((r['tags']! as List<Object?>), isNotEmpty);
  });

  testWidgets('supportedLanguages reports real locales', (_) async {
    final List<String> languages =
        await AppleFoundationModels.supportedLanguages();
    expect(languages, isNotEmpty);
    expect(languages.any((String l) => l.startsWith('en')), isTrue);
  });

  testWidgets('availabilityChanges opens with the current value', (_) async {
    expect(
      await AppleFoundationModels.availabilityChanges.first,
      const ModelAvailable(),
    );
  });

  testWidgets('deltas() reconstructs the response exactly', (_) async {
    final List<String> snapshots = <String>[];
    final StringBuffer joined = StringBuffer();

    final Stream<String> source = session.stream('Name three trees.');
    await for (final String snapshot in source) {
      snapshots.add(snapshot);
    }

    // Same prompt twice would give different text, so diff the captured run.
    await for (final String delta in Stream<String>.fromIterable(
      snapshots,
    ).deltas()) {
      joined.write(delta);
    }
    expect(
      joined.toString(),
      snapshots.last,
      reason: 'concatenated deltas must equal the final snapshot',
    );
  });

  testWidgets('respondInto decodes into a Dart type', (_) async {
    final ({String summary, int severity}) triage = await session.respondInto(
      'Triage: the login button does nothing on iPad.',
      schema: Schema.object(<String, Schema>{
        'summary': Schema.string(description: 'one line'),
        'severity': Schema.integer(min: 1, max: 5),
      }),
      decoder: (Map<String, Object?> json) => (
        summary: json['summary']! as String,
        severity: (json['severity']! as num).toInt(),
      ),
      options: GenerationOptions.deterministic,
    );

    expect(triage.summary, isNotEmpty);
    expect(triage.severity, inInclusiveRange(1, 5));
  });

  testWidgets('a disposed session refuses further work', (_) async {
    final LanguageModelSession temp = await LanguageModelSession.create();
    await temp.dispose();
    expect(temp.isDisposed, isTrue);
    expect(() => temp.respond('hello'), throwsStateError);
  });

  testWidgets('duplicate tool names are rejected up front', (_) async {
    LanguageModelTool tool(String name) => LanguageModelTool(
      name: name,
      description: 'x',
      parameters: Schema.object(<String, Schema>{'a': Schema.string()}),
      handler: (_) => 'ok',
    );
    await expectLater(
      LanguageModelSession.create(
        tools: <LanguageModelTool>[tool('same'), tool('same')],
      ),
      throwsArgumentError,
    );
  });
}
