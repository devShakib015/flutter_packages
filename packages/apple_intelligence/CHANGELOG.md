## 0.3.0

An audit of every package in this repo found six defects here.

### Fixed

- **`import 'dart:io'` made the package impossible to compile for web,** while
  the docs promised `fallback` rendered there. Replaced with
  `defaultTargetPlatform`.
- **A second concurrent `generate()` silently stole the first one's events.**
  Each run opened its own `receiveBroadcastStream().listen`, and a second
  listen re-sends `listen` to the platform, which replaces the sink — so the
  first stream hung forever with no error and no close. There is one
  subscription now, demultiplexed by the run id the native side already stamps
  on every event.
- **`capabilities()` answered "did I configure it", not "will it work".** It
  read back `writingToolsBehavior` and `supportsAdaptiveImageGlyph` — values
  this plugin had set moments earlier — so it returned true on every iOS 18
  device, including ones with Apple Intelligence switched off or still
  downloading. It is ANDed with the system's own availability flag now.
- **The text field ignored rebuilds.** `readOnly` and `fontSize` were
  creation-only, so a field switched to read-only stayed editable; swapping the
  controller left the new one attached to nothing, so every call on it did
  nothing at all. `didUpdateWidget` handles both, with a new native
  `configure`.

### Known, not fixed

- An inserted Genmoji still cannot be read back: `getText()` and `onChanged`
  give U+FFFC where the glyph is, and `setText()` removes it. A faithful round
  trip needs an attributed-string channel (RTFD, or per-attachment identifiers)
  rather than the plain-string one this uses.
- On macOS the platform-view host and its `NSScrollView` retain each other, so
  a text field is not deallocated. Breaking it properly means restructuring the
  host, which is more than a patch release should carry.

## 0.2.2

- `exceptionFor`, the internal helper that maps a platform error code to a
  typed exception, was public API. The barrel exported three files wholesale,
  and a wholesale export carries top-level functions as well as classes — so a
  private mapping function became something callers could reach and something
  that could not be changed without a breaking release. Every export now names
  what it exposes.
- README code blocks now parse. Several listed variants one per line without
  terminating semicolons; each is checked through the analyser now.

Technically breaking if you were calling `exceptionFor`, which you had no
reason to.

## 0.2.1

Documentation only — no API or behaviour changes.

- Adds a recording of a real generation run to the README and to the pub.dev
  page. Four images in 28 seconds, each appearing as it arrived; the elapsed
  clock in the frames is the genuine one.
- Recording it needed a different approach from the other packages here. The
  usual `flutter test` frame recorder runs headless, and Apple refuses image
  creation to an app that is not frontmost, so the app records itself. Capture
  is driven by images arriving rather than by a timer, because macOS throttles
  timers and a stalled ticker silently truncates the run.

## 0.2.0

Writing Tools and Genmoji, via a real system text view.

- `AppleIntelligenceTextField` hosts a genuine `UITextView`/`NSTextView` inside
  Flutter, which is what makes Apple's text features work at all: Writing Tools
  attaches to a `UIView` and Genmoji is a property of `UITextInput`, and a
  Flutter text field is neither as far as the system is concerned.
- `NativeTextController` reads and writes the contents, and `capabilities()`
  asks the live view what it was actually granted rather than inferring it from
  the OS version.
- `onChanged` fires when the native view edits itself — which is the only way to
  notice that Writing Tools rewrote your text or a Genmoji was inserted.

This is deliberately **not** a drop-in for Flutter's `TextField`. It is a
platform view, so it composites differently and costs more; styling does not
inherit from your theme; and it exists on iOS and macOS only, rendering
`fallback` elsewhere. The README says so before it says anything else about it.

Verified on macOS: the hosted view reports `writingTools: true, genmoji: true`,
and text round-trips through the controller.

## 0.1.0

Initial release: Apple Intelligence image generation for Flutter.

- `ImageCreator.generate` produces images on device with no UI, delivered as a
  `Stream` so the first can be shown while the rest are still being made.
  Cancelling the subscription cancels the work on the device.
- `ImagePlaygroundSheet.present` shows Apple's own generation UI and returns the
  file it wrote, or null if the user cancelled.
- `ImageCreator.availability` reports the sheet and streaming separately,
  because the sheet is iOS 18.1 and streaming is 18.4 — a device can offer one
  and not the other.
- `ImageConcept.text` names a subject; `ImageConcept.extractedFrom` asks the
  system to find the subjects in a passage.
- Errors arrive as a typed hierarchy — `OsTooOldException`,
  `GenerationUnavailableException`, `GenerationRefusedException` with a specific
  reason — never as a bare `PlatformException`.

Verified against real Apple Intelligence hardware: two PNGs of about 4 MB, the
first at 6.8s and the second at 10.3s.

**Not included:** Writing Tools and Genmoji. Both are planned; Writing Tools
attaches to a native text view while Flutter renders its own text, so it needs a
design decision rather than a wrapper.
