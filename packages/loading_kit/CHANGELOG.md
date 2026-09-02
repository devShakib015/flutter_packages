## 0.3.2

An audit of every package in this repo found five defects here. This package
has the thinnest test coverage in the repo — 4,379 lines of library against 36
tests — and it showed.

### Fixed

- **A nested `LoadingHost` permanently killed the global `Loading` facade.**
  Attachment was a single field, so a nested host replaced the root on mount
  and set the facade to null on unmount — after which every `Loading.show()`
  anywhere in the app threw `LoadingHostMissing`, even though the root host was
  still mounted. One modal with its own host poisoned the whole app.
  Attachment is a stack now: innermost wins while mounted, and unmounting hands
  the facade back.
- **`show(dismissible: true)` rendered a scrim that did nothing.** The scrim
  calls `cancelTopmost()`, which looks for an operation carrying an `onCancel`
  — and only `run`/`runTask` ever set one. So a tap did nothing, or found some
  unrelated operation further down the stack and cancelled *that*. A dismissible
  `show` now carries its own cancel.
- **A route push while loading crashed under the pages API.**
  `LoadingNavigatorObserver` cleared synchronously inside `didPush`, which the
  pages API runs during the build phase, and clearing mutates a notifier the
  overlay listens to — "setState() called during build". It defers past the
  frame when something is building, and still runs inline when nothing is.
- **An error cross turned into a green success tick as it animated away.** The
  painter takes its glyph and colour from the current status, so flipping back
  to busy mid-morph recoloured the outgoing glyph. The terminal identity is now
  held for the length of the morph.
- **The README told you to install a version that excludes this one.** The
  install block pinned `^0.1.0` — which resolves to `>=0.1.0 <0.2.0` — so
  anyone copying it landed on 0.1.x and missed the 0.3.0 breaking change
  entirely. Its only token-override snippet also passed `scrimBlur:`, which is
  not a parameter; the field is `backdropBlur`.

## 0.3.1

Documentation only — no API changes.

- README code blocks now parse. Several listed variants one per line without
  terminating semicolons, so copying a block gave a syntax error even though
  each individual line was fine. Every snippet in this README is now checked
  through the analyser.

## 0.3.0

**Breaking, though probably not for you.** The barrel used to re-export whole
files, which made every public member in them public API by accident. Three
package internals were reachable as a result — `LoadingOperation`,
`ResolvedLoadingStyle` and `LoadingIndicatorPainter`. Two of them say
"internal" in their own doc comments. They are hidden now.

Nothing else changed, and nothing documented has moved. If you were importing
one of those three, you were reaching into the plumbing; open an issue and say
what for, and it can be exposed deliberately instead of by accident.

The exports are written with explicit `show` clauses now, so what is public is
a decision rather than a side effect of file layout.

**Documentation.** The Usage section opened with `Loading.run(...)`, while the
README went on to recommend `context.loading.run(...)` three hundred lines
later. A newcomer copies the first example, so the first example now shows
both and says which to prefer and why.

## 0.2.1

Packaging only — no API or behaviour changes.

- The demo animations now ship inside the package, so they appear as
  screenshots on the pub.dev page rather than only in the README on GitHub.
- `.pubignore` excludes the raw recorder frames, so shipping them costs
  about 1.7 MB rather than the 11 MB the frame directory would have added.

## 0.2.0

Everything is now a token. Nothing about the indicator, the card, or the
toasts is hardcoded any more.

### Added
- `LoadingMotion` controls animation speed: `spinPeriod`, `morphDuration`,
  `progressDuration`, `barSweepPeriod`, `crossFadeDuration`. Ships with
  `standard`, `brisk` and `calm` profiles.
- `LoadingToastStyle` controls toast chrome: padding, radius, icon size and
  stroke, gaps, enter duration.
- Card metrics as tokens: `cardMinWidth`, `textGap`, `cancelMinimumSize`,
  `cancelPadding`.
- `LoadingProgressBar` takes `sweepPeriod` and `fillDuration` directly.
- `LoadingController` takes `toastExitDuration`, `defaultToastDuration` and
  `maxVisibleToasts`.

### Fixed
- A `cardMinWidth` above `maxCardWidth` produced non-normalized constraints and
  threw. The pair is now clamped, since both come from the caller.

### Breaking
- `LoadingController.toastExitDuration`, `defaultToastDuration` and
  `maxVisibleToasts` moved from statics to instance fields set on the
  constructor. The `duration` argument to `toast` is now nullable and falls
  back to the controller's own default.

## 0.1.0

Initial release.

### Indicators
- Six indeterminate forms — `arc`, `dots`, `bars`, `orbit`, `pulse`, `ripple` —
  all settling into the same check or cross.
- `indicatorBuilder` replaces the built-in indicator with any widget, so Lottie,
  Rive, or another spinner package can be dropped straight in.
- `LoadingProgressStyle.bar` draws determinate progress as a linear bar.

### Beyond the full-screen overlay
- `Loading.toast` / `toastSuccess` / `toastError` for transient, non-blocking
  messages that never intercept input.
- `LoadingBarrier` scopes the overlay to a single subtree while still applying
  the timing policy.

- `Loading.run` / `runTask` wrap a future behind the overlay in one call.
- Timing policy with a reveal delay and a minimum-visible window, so fast
  operations paint nothing and slow ones do not blink out.
- Reference counting across concurrent operations, with a running operation
  outranking one that has already settled.
- Determinate progress, cooperative cancellation, and timeouts.
- Success and error states drawn as one continuous morph of the arc rather
  than a widget swap.
- Five presets — `cupertino`, `material`, `glass`, `minimal`, `neon` — plus
  `adaptive`, all resolving against the ambient theme in light and dark.
- Route awareness via `LoadingNavigatorObserver`.
- Input blocking, focus trapping, live-region announcements, `BlockSemantics`,
  and reduced-motion support.
- `LoadingIndicator` usable standalone, with no overlay or controller.
