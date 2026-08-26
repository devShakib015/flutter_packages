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
