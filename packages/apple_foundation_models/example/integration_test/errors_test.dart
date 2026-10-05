import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The framework's own errors, raised by the real model.
///
/// Built with Xcode 27, FoundationModels stops throwing
/// `LanguageModelSession.GenerationError` and throws `LanguageModelError` and
/// friends instead — Xcode 26 builds keep the old type. A plugin that only
/// knew the old type turned every one of these into the generic
/// [FoundationModelsPlatformException], so these assert the exact subtype.
///
///   flutter test integration_test/errors_test.dart -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('a prompt past the context window is ContextWindowExceeded',
      (_) async {
    final LanguageModelSession session = await LanguageModelSession.create();
    addTearDown(session.dispose);

    // Far past any on-device context size: about 60,000 tokens.
    final String flood =
        List<String>.filled(30000, 'harbour lantern').join(' ');
    Object? caught;
    try {
      await session.respond('Summarise this: $flood');
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<ContextWindowExceededException>(),
        reason: 'got ${caught.runtimeType}: $caught');
  });

  testWidgets('the session is still usable after the overflow', (_) async {
    final LanguageModelSession session = await LanguageModelSession.create();
    addTearDown(session.dispose);

    final String flood =
        List<String>.filled(30000, 'harbour lantern').join(' ');
    await expectLater(
      session.respond('Summarise this: $flood'),
      throwsA(isA<ContextWindowExceededException>()),
    );
    expect(await session.respond('Say hello.'), isNotEmpty);
  });
}
