## 0.1.0

Initial release.

- `AppleFoundationModels.availability()` with typed reasons — `deviceNotEligible`,
  `appleIntelligenceNotEnabled`, `modelNotReady`, `osTooOld`,
  `unsupportedPlatform` — each carrying an explanation and, where one exists,
  a remedy.
- `LanguageModelSession` with instructions, transcript, `prewarm`, and
  `isResponding`.
- Four response modes: `respond`, `respondAs` (schema-constrained),
  `stream`, and `streamAs` (structured output arriving progressively).
- A Dart schema DSL — objects, arrays, enums, optional fields — rebuilt
  natively as a `DynamicGenerationSchema`, so typed output needs no codegen.
- Tool calling: the model invokes a Dart function mid-generation and waits
  for the result.
- `GenerationOptions` with temperature, token cap, and greedy / top-k / top-p
  sampling.
- Every framework error mapped to its own exception type.
- Compiles and runs on every platform. Non-Apple targets report
  `unsupportedPlatform` instead of failing the build, and an Xcode without the
  iOS 26 SDK still compiles.
