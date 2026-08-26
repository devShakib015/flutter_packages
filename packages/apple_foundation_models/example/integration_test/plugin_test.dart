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
