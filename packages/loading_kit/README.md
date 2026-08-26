# loading_kit

A blocking-async overlay that never flickers.

Wrap a future in one call. `loading_kit` decides whether an overlay is even
warranted, holds it long enough to read, counts overlapping requests, settles
into a check or a cross, and cleans up after itself when the route changes.

```dart
final user = await Loading.run(
  () => api.signIn(email, password),
  message: 'Signing in…',
  successMessage: 'Welcome back',
);
```

![The same 80ms request, then the same 1.2s request, with and without loading_kit](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/loading_kit/doc/antiflicker.gif)

*Left: a bool and a Stack. Right: loading_kit. Same requests, fired at the same moment.*

## Why another one

Most loading overlays are a spinner in a `Stack` with a `bool`. They work until
the network is fast, and then they strobe: a request returns in 90ms, the
spinner appears and vanishes inside three frames, and the screen flinches.

Two rules fix that, and they are the reason this package exists.

**Nothing paints before the reveal delay.** An operation that resolves in under
140ms renders nothing at all — not a spinner, not a success tick. Fast paths
stay visually silent. In the GIF above the left panel gets a single frame of
spinner; the right panel never moves.

**Once painted, it holds.** An overlay that appeared at 140ms and tore down at
170ms reads as a glitch, so it stays for at least half a second. The wait is
deliberate, and it looks deliberate.

Everything else in the package follows from taking blocking state seriously
rather than from having more spinner shapes.

## Install

```yaml
dependencies:
  loading_kit: ^0.1.0
```

## Setup

One line in your app, plus an observer so overlays cannot outlive their screen.

```dart
MaterialApp(
  builder: LoadingKit.builder(style: LoadingStyle.glass),
  navigatorObservers: [LoadingNavigatorObserver()],
  home: const HomePage(),
);
```

The host sits above the navigator, so the overlay covers every route — dialogs
and bottom sheets included — and survives transitions underneath it.

## Usage

### Run a future

```dart
final orders = await Loading.run(() => repo.fetchOrders());
```

`run` rethrows whatever the task threw, so your error handling is unchanged.
Its future completes only once the overlay has finished leaving — returning
earlier would let you navigate out from under a still-animating overlay, which
is the flicker this package exists to prevent. Pass `awaitFeedback: false` to
opt out.

### Report progress and allow cancelling

```dart
await Loading.runTask((task) async {
  for (var i = 0; i < files.length; i++) {
    task.throwIfCancelled();
    task.report((i + 1) / files.length, detail: '${i + 1} of ${files.length}');
    await upload(files[i]);
  }
}, message: 'Uploading…', cancelAfter: const Duration(seconds: 3));
```

`cancelAfter` reveals the cancel affordance only once that much time has
passed, so quick operations never offer one. Cancellation is cooperative:
tapping cancel rejects the future with `LoadingCancelled` immediately, and the
body stops at its next `throwIfCancelled()`.

### Drive it by hand

```dart
final upload = Loading.show(message: 'Preparing…');
upload.update(message: 'Compressing…', progress: 0.2);
upload.progress = 0.85;
await upload.success('Done');
```

### Time out

```dart
await Loading.run(
  () => api.slowCall(),
  timeout: const Duration(seconds: 20),
  errorMessage: 'Timed out',
);
```

### Use the indicator alone

`LoadingIndicator` needs no overlay and no controller.

```dart
const LoadingIndicator(size: 48)
LoadingIndicator(progress: 0.6)
LoadingIndicator(status: LoadingStatus.success)
LoadingIndicator(indicatorStyle: LoadingIndicatorStyle.ripple)
```

### Toasts, for things that already happened

Not everything deserves a scrim. A toast reports an outcome without blocking
anything, and dismisses itself:

```dart
Loading.toast('Draft saved');
Loading.toastSuccess('Order placed');
Loading.toastError('Could not sync', detail: 'Retrying in the background');
```

Toasts never intercept input, stack up to three at a time, and reuse the
resolved theme so they match the overlay.

### Block one part of the screen, not all of it

Blacking out the whole app for a form that saves in place is heavy-handed.
`LoadingBarrier` scopes the overlay to a subtree — and still applies the
timing policy, so a fast save flashes nothing:

```dart
LoadingBarrier(
  loading: _saving,
  message: 'Saving…',
  borderRadius: BorderRadius.circular(16),
  child: const ProfileForm(),
)
```

### A bar instead of a ring

For long operations a bar is easier to read at a glance — the difference
between 60% and 70% is obvious in a line and subtle in a circle:

```dart
LoadingStyle.material.copyWith(progressStyle: LoadingProgressStyle.bar)
```

The outcome still arrives as the glyph, so a finished bar cross-fades to a
check or a cross.

## Presets

`adaptive` (the default) resolves to `cupertino` on Apple platforms and
`material` elsewhere. Every preset resolves against the ambient `ThemeData`, so
light and dark both work with no configuration.

| Preset | Look |
| --- | --- |
| `cupertino` | Compact, low-contrast card in the iOS idiom |
| `material` | Tonal Material 3 surface using your primary colour |
| `glass` | Frosted translucent panel with a luminous edge |
| `minimal` | Indicator only on a soft scrim — cheapest to paint |
| `neon` | Dark panel with a saturated, glowing indicator |

![The five presets](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/loading_kit/doc/presets.gif)

## Indicator styles

Six indeterminate forms. Every one settles into the same check or cross, so
the outcome reads identically no matter which spinner preceded it.

![The six indicator styles](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/loading_kit/doc/styles.gif)

```dart
LoadingStyle.material.copyWith(indicatorStyle: LoadingIndicatorStyle.bars)
```

`arc` · `dots` · `bars` · `orbit` · `pulse` · `ripple`

Determinate work always draws as an arc or a bar regardless of this setting —
no pulsing or bouncing form can express "62%".

### Or bring your own

The built-in shapes are optional. `indicatorBuilder` hands the whole slot to a
widget of yours — a Lottie file, a Rive animation, your brand mark, or anything
from another spinner package:

```dart
LoadingKit.builder(
  style: LoadingStyle.material.copyWith(
    indicatorBuilder: (context, spec) => SpinKitCubeGrid(
      color: spec.statusColor,
      size: spec.size,
    ),
  ),
)
```

`spec` carries the resolved status, progress, size, colours and stroke width,
so a custom indicator still tracks your theme.

Override any token without leaving the preset:

```dart
LoadingKit.builder(
  style: LoadingStyle.cupertino.copyWith(
    indicatorColor: brand.teal,
    cardRadius: BorderRadius.circular(20),
    scrimBlur: 12,
  ),
)
```

Tune the timing the same way:

```dart
LoadingKit.builder(
  timing: const LoadingTiming(
    delay: Duration(milliseconds: 180),
    minVisible: Duration(milliseconds: 600),
  ),
)
```

`LoadingTiming.instant` disables both rules, and `LoadingTiming.relaxed` waits
longer before committing for operations you expect to be slow.

## What it handles that a `bool` does not

- **Reference counting.** Two concurrent calls stack. The overlay leaves when
  the last one retires, so an early return cannot strand another request.
- **Busy outranks settled.** If one request succeeds while another is still
  running, the spinner stays. No check mark flashes mid-flight.
- **Route awareness.** `LoadingNavigatorObserver` clears overlays when the
  route beneath them changes, so a spinner cannot get stuck over a screen that
  never asked for it.
- **Input blocking.** An opaque hit target swallows every tap bound for the app
  behind it.
- **Focus trapping.** The blocked app is pulled out of focus traversal, so a
  hardware keyboard cannot reach buttons under the scrim.
- **Screen readers.** The overlay is a live region that announces its message
  and its progress, and `BlockSemantics` hides the blocked app underneath.
- **Reduced motion.** The entrance scale is dropped when the platform asks for
  fewer animations.
- **One continuous form.** Spinner, progress arc, check and cross are a single
  `CustomPainter`. The arc closes into a ring, crosses to the terminal colour,
  and strokes the glyph on inside it — rather than swapping one widget for an
  unrelated one.

  ![The arc closing into a check, then a cross](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/loading_kit/doc/morph.gif)

## Performance

- **Free while idle.** With nothing in flight the overlay builds a
  `SizedBox.shrink()`: no scrim, no blur, no ticker, no hit-test target.
- **Your app is not rebuilt.** The overlay listens to one `ValueListenable` and
  rebuilds one small subtree. The app subtree is passed through by identity, so
  Flutter skips it entirely when loading starts or stops.
- **The spinner stops when it settles.** Reaching success or error halts the
  repeating ticker rather than leaving it running through the exit animation.
- **Blur is opt-in and scoped.** Only the `glass` and `neon` presets blur, and
  the filter is clipped to the card rather than compositing the whole screen.
- **One painter, one repaint boundary.** No stacked opacity layers, no
  `saveLayer` for the indicator.

## Testing

Everything is timer-driven, so timing behaviour is testable on the fake clock
with no real waiting:

```dart
testWidgets('a fast call shows nothing', (tester) async {
  final controller = LoadingController();
  addTearDown(controller.dispose);

  final work = controller.run(() => Future.delayed(const Duration(milliseconds: 80)));
  await tester.pump(const Duration(milliseconds: 80));
  expect(controller.value.visible, isFalse);

  await tester.pump(const Duration(milliseconds: 400));
  await work;
});
```

One caveat that applies to any indeterminate indicator, Flutter's own included:
a spinning arc schedules a frame forever, so `pumpAndSettle()` will not settle
while one is on screen. Pump explicit durations instead.

## Scoped controllers

The global `Loading` facade is a convenience for code with no `BuildContext`.
Where a context is available, prefer the scoped controller — it is ordinary
state rather than shared state, and trivially testable:

```dart
await context.loading.run(() => repo.save(draft));
```

You can also host an overlay over part of the app rather than all of it:

```dart
LoadingHost(
  registerGlobal: false,
  controller: myController,
  child: const EditorPane(),
)
```

## License

MIT © K M Shahriar Hossain

## Regenerating the demos

The GIFs are produced by driving the package through Flutter's own rasterizer
on a fake clock, so they show the real timing frame-accurately rather than
whatever a screen recorder happened to catch.

    flutter test tool/record_frames.dart   # writes doc/frames/<scene>/*.png
    ./tool/build_gifs.sh                   # writes doc/<scene>.gif
