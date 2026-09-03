## 0.3.2

Corrects 0.3.1, which claimed a floor it had not actually been checked against.

0.3.1 added `package:meta` so `Bridge` could carry `@internal`. That constraint
does not resolve on older SDKs, so the package would not have installed at the
floor its own changelog advertised — and the check that was supposed to catch
this reported success because the analyzer never ran at all. The verification
now proves the analyzer executed before trusting a zero error count.

`@internal` is gone, and with it the dependency. `Bridge` lives under `lib/src/`
and the barrel never exports it, so it was already unreachable; the annotation
bought nothing and cost a resolution failure.

Genuinely type-checked against Flutter 3.16.9 / Dart 3.2.6 this time, against a
declared floor of Flutter 3.24.

## 0.3.1

No behaviour changes. `sdk: ^3.13.0` meant Dart 3.13, which ships only with
**Flutter 3.47** — released three weeks ago — so this package refused to resolve
for anyone on an older SDK. One null-aware element (Dart 3.8) was all that
required it; rewritten, the floor is now `^3.5.0` / Flutter 3.24 and verified by
type-checking against Flutter 3.16.9.

## 0.3.0

An audit of every package in this repo found four defects here.

### Fixed

- **Two enum fields in one schema were rejected at runtime.** The native side
  mints one Swift type per node and named every unnamed enum `Choice`, so a
  schema with two of them declared the same type twice — and a classification
  schema, which is what enums are for, usually has more than one. Unnamed
  objects collided the same way on `Result`. Names are minted uniquely when a
  schema is serialised, and `Schema.oneOf` takes a `name` when you want a
  particular one.
- **`ToolCallException` and `SchemaException` were unreachable for anything
  the framework raised.** A tool that threw arrives wrapped in
  `LanguageModelSession.ToolCallError` with the real error nested inside, and
  the payload builder only matched this plugin's own types — so every
  framework-raised failure collapsed into the generic fallback and lost the
  tool name with it. The wrapper is unwrapped first now.
- **The in-flight task dictionary was a data race.** It was written from the
  platform thread when a request started and from the cooperative pool when it
  finished, with no synchronisation. On a Swift Dictionary that is heap
  corruption, not a wrong answer. Every access is on the main queue now.
- **The README told you to install a version that excludes this one.** The
  install snippet pinned `^0.1.0`, which resolves to `>=0.1.0 <0.2.0`. The
  0.2.1 note claimed every snippet in the README was analyser-checked, which a
  YAML block escapes.

## 0.2.1

Documentation only — no API changes.

- README code blocks now parse. Several listed variants one per line without
  terminating semicolons, so copying a block gave a syntax error even though
  each individual line was fine. Every snippet in this README is now checked
  through the analyser.

## 0.2.0

**Renamed `LoadingStreamDeltas` to `ModelStreamDeltas`.** The old name was
copy-paste from a sibling package and had nothing to do with loading anything.
It matters more than a private misnomer would: this is an extension on
`Stream<String>`, so importing this package put that wrong name into the tools
of anyone with a string stream anywhere in their app.

Nothing about the behaviour changed, and `deltas()` is called the same way. You
would only notice if you had written the extension name explicitly, which is
rare — but it is a breaking change, so it gets a minor bump.

- The transcript API is documented now. `session.transcript()` and
  `TranscriptRole` were public and appeared in neither the README nor the
  example, so reading back what a session was told meant reading the source.

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
