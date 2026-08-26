/// Run Apple's on-device language model from Flutter.
///
/// Private, offline, and free — nothing leaves the device and there is no API
/// key. Requires iOS 26 or macOS 26 on Apple Intelligence hardware, so always
/// check [AppleFoundationModels.availability] before showing an AI feature.
///
/// ```dart
/// if (!await AppleFoundationModels.isAvailable) return;
///
/// final session = await LanguageModelSession.create(
///   instructions: 'You summarise text in one sentence.',
/// );
/// print(await session.respond(article));
/// await session.dispose();
/// ```
library;

export 'src/availability.dart';
export 'src/exceptions.dart';
export 'src/generation_options.dart';
export 'src/schema.dart';
export 'src/session.dart';
export 'src/stream_extensions.dart';
export 'src/tool.dart';
export 'src/transcript.dart';
export 'src/use_case.dart';
