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
