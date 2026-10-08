import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// What the model says about itself, what a session spends, and moving a
/// conversation between models — against the real model.
///
///   flutter test integration_test/model_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late bool on27;

  setUpAll(() async {
    final ModelAvailability availability =
        await AppleFoundationModels.availability();
    if (availability is ModelUnavailable) {
      fail(
        'Model unavailable (${availability.reason.name}). '
        '${availability.explanation} ${availability.remedy ?? ''}',
      );
    }
    // Images arrived with the same release as names, capabilities and usage.
    on27 = await AppleFoundationModels.supportsImages();
  });

  testWidgets('modelInfo names the model and what it can do', (_) async {
    final ModelInfo general = await AppleFoundationModels.modelInfo();
    final ModelInfo tagging = await AppleFoundationModels.modelInfo(
      useCase: ModelUseCase.contentTagging,
    );
    debugPrint('general: $general');
    debugPrint('contentTagging: $tagging');

    expect(general.contextSize, greaterThan(0));
    if (!on27) return markTestSkipped('Names and capabilities need 27.');
    expect(general.name, isNotEmpty);
    expect(general.can(ModelCapability.toolCalling), isTrue);
    expect(general.can(ModelCapability.guidedGeneration), isTrue);
    expect(general.can(ModelCapability.vision), isTrue);
  });

  testWidgets('tokenCount grows with the text', (_) async {
    final int? short = await AppleFoundationModels.tokenCount('Hello there.');
    final int? long = await AppleFoundationModels.tokenCount(
      List<String>.filled(200, 'harbour lantern').join(' '),
    );
    if (short == null) return markTestSkipped('Token counts need 26.4.');
    expect(short, greaterThan(0));
    expect(long, greaterThan(short * 20));
  });

  testWidgets('usage counts each request, and readings subtract', (_) async {
    final LanguageModelSession session = await LanguageModelSession.create(
      instructions: 'Answer in as few words as possible.',
    );
    addTearDown(session.dispose);

    final TokenUsage? start = await session.usage();
    if (start == null) return markTestSkipped('Usage needs 27.');

    await session.respond('Say hello.');
    final TokenUsage first = (await session.usage())!;
    await session.respond('Say goodbye.');
    final TokenUsage second = (await session.usage())!;

    final TokenUsage one = first - start;
    final TokenUsage two = second - first;
    debugPrint('first request: $one\nsecond request: $two');
    expect(one.inputTokens, greaterThan(0));
    expect(one.outputTokens, greaterThan(0));
    expect(two.outputTokens, greaterThan(0));
    // The second request resends the first exchange as context.
    expect(two.inputTokens, greaterThan(one.inputTokens));
  });

  testWidgets('switchModel keeps the conversation, its tools and its usage',
      (_) async {
    bool toolCalled = false;
    final LanguageModelSession session = await LanguageModelSession.create(
      instructions: 'Answer in as few words as possible.',
      tools: <LanguageModelTool>[
        LanguageModelTool(
          name: 'getTime',
          description:
              'The current time. Always call this when asked the time.',
          parameters: Schema.object(<String, Schema>{
            'zone': Schema.string(description: 'timezone name'),
          }),
          handler: (_) {
            toolCalled = true;
            return '10:42';
          },
        ),
      ],
    );
    addTearDown(session.dispose);

    await session.respond(
      'Remember this code word: lantern. Reply with just OK.',
      options: GenerationOptions.deterministic,
    );
    final int entries = (await session.transcript()).length;
    final TokenUsage? before = await session.usage();

    await session.switchModel(ModelUseCase.contentTagging);
    expect(session.useCase, ModelUseCase.contentTagging);
    expect((await session.transcript()).length, entries,
        reason: 'the new model starts from the same transcript');
    final Map<String, Object?> tags = await session.respondAs(
      'Tag the topic of this conversation.',
      schema: Schema.object(<String, Schema>{
        'tags': Schema.array(Schema.string(), maxItems: 3),
      }),
    );
    expect(tags['tags'], isA<List<Object?>>());

    await session.switchModel(ModelUseCase.general);
    final String word = await session.respond(
      'What was the code word I asked you to remember? Answer with the word only.',
      options: GenerationOptions.deterministic,
    );
    expect(word.toLowerCase(), contains('lantern'),
        reason: 'the conversation survived two switches');

    await session.respond('What time is it in Dubai?');
    expect(toolCalled, isTrue, reason: 'the tools survived too');

    final TokenUsage? after = await session.usage();
    if (before != null) {
      expect(after!.inputTokens, greaterThan(before.inputTokens),
          reason: 'usage is a running total across switches');
    }
  });

  testWidgets('switching mid-request is refused', (_) async {
    final LanguageModelSession session = await LanguageModelSession.create();
    addTearDown(session.dispose);

    final Future<String> first = session.respond(
      'Write a detailed paragraph about the sea.',
    );
    await expectLater(
      session.switchModel(ModelUseCase.contentTagging),
      throwsA(isA<ConcurrentRequestException>()),
    );
    await first;
    expect(session.useCase, ModelUseCase.general);
  });
}
