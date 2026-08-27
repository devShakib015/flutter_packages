## 0.1.2

Packaging only — no API or behaviour changes.

- The demo animations now ship inside the package, so they appear as
  screenshots on the pub.dev page rather than only in the README on GitHub.
- `.pubignore` excludes the raw recorder frames, so shipping them costs
  about 360 KB rather than the 11 MB the frame directory would have added.

## 0.1.1

Fixes a macOS build failure under Swift Package Manager.

`Package.swift` declared only `.iOS("15.0")` and no macOS platform. SPM defaults
an undeclared platform to macOS 10.13, where Swift concurrency's `Task` does not
exist, so the plugin failed to compile with `'Task' is only available in macOS
10.15 or newer`. The podspec had always said `osx 10.15`, so CocoaPods builds
were unaffected and the two paths disagreed — and SPM is on by default on
current Flutter, so most macOS users would have hit this.

No API changes.

## 0.1.0

Initial release.

- Generation guides: `Schema.integer(min:, max:)`, `Schema.number(min:, max:)`,
  `Schema.string(pattern:)`, `Schema.array(exactItems:)`. Bounds constrain
  generation itself, so a 1-to-5 rating cannot come back as 47.
- `respondInto` / `streamInto` decode straight into your own types.
- `deltas()` turns cumulative snapshots into increments.
- `ModelUseCase.contentTagging` selects Apple's tagging-tuned model.
- `AppleFoundationModels.supportedLanguages()` and `availabilityChanges`, the
  latter firing when the model finishes downloading mid-session.

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
