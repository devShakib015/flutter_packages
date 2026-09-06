# document_pip

Live Flutter widgets in a real, always-on-top operating-system window — from
Flutter Web.

![The page and a real always-on-top pop-out window, one paused player in both](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/document_pip/doc/popout.png)

*Two windows, one widget tree. The pop-out is a real OS window — it stays above every other application, and it keeps running when you switch tabs.*

Not a widget floating inside your app. An actual window the browser owns, which
stays above your editor, your terminal and every other application, while your
app keeps running with its state intact.

```dart
void main() => runWidget(
  DocumentPipApp(
    main: (context) => const MaterialApp(home: Player()),
    popOut: (context) => const MaterialApp(home: MiniPlayer()),
  ),
);

// ...in a button handler:
final window = await DocumentPip.open(width: 380, height: 210);
await window.closed;
```

State lifted above `DocumentPipApp` is shared, so both windows are looking at
the same objects. Scrub in one and the other moves, because there is only one.

## Two things this needs that a normal package does not

Multi-view is a property of how the engine starts, so it cannot be switched on
from inside a package. Both of these are one-time, and the errors tell you if
you miss them.

**1. `runWidget`, not `runApp`.** Multi-view Flutter has no single root.

**2. A bootstrap that turns multi-view on and hands over the app runner.** Only
the JS app object returned by `engine.runApp()` can add a view — `dart:ui_web`
exposes the views read-only — so it has to be reachable. In
`web/flutter_bootstrap.js`:

```js
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { multiViewEnabled: true },
  onEntrypointLoaded: async function (engineInitializer) {
    const engine = await engineInitializer.initializeEngine({
      multiViewEnabled: true,
    });
    const app = await engine.runApp();
    window.documentPipApp = app;          // <- document_pip needs this

    // In multi-view mode no view is created for you.
    app.addView({ hostElement: document.querySelector('#app') });
  },
});
```

and give `web/index.html` a host to point at:

```html
<body style="margin:0;height:100%">
  <div id="app" style="position:absolute;inset:0"></div>
</body>
```

Forget the bootstrap and `DocumentPip.open()` throws
`DocumentPipNotBootstrapped`, whose message is this snippet verbatim — a test
keeps the two identical. Forget `runWidget` and you never get that far: Flutter
itself refuses to start and names the fix.

Never pass `document.body` as the host. Flutter clears a host element's
children and sizes the view to 100% of it, so `body` wipes your page — script
tags included — and then measures zero.

## Install

```bash
flutter pub add document_pip
```

## Opening the window

```dart
if (!DocumentPip.isSupported) return;   // see browser support below

final window = await DocumentPip.open(
  width: 380,
  height: 210,
  copyStyles: true,             // the new document starts with none
  disallowReturnToOpener: false,
  preferInitialWindowPlacement: false,  // true to ignore the remembered size
);

window.viewId;                  // the Flutter view rendering inside it
window.isOpen;
await window.closed;            // however it closed
await window.close();
```

**`open()` must be the first `await` in a user-gesture handler.** The browser
only allows this while handling a real click, tap or key press, and awaiting
anything beforehand spends that gesture. Load your data afterwards:

```dart
onPressed: () async {
  final window = await DocumentPip.open();   // first
  final data = await fetchTrack();           // then
}
```

Get that wrong and you get `DocumentPipDenied`. Chrome refuses for three
reasons and calls all of them `NotAllowedError`, so the message lists them and
quotes Chrome's own text, which is the part that actually discriminates. The
other common one is calling from inside an iframe.

## It keeps running when you switch tabs

Which is the whole point, and is not free. Chromium keeps painting the page
that owns a picture-in-picture window even when its tab is in the background —
but it still reports that page as `hidden`, and Flutter responds to `hidden` by
switching frames off. Left alone, the floating window freezes the instant you
look at something else.

`DocumentPipApp` is what stops that, by forcing frames for exactly as long as
the page is hidden and a window is open. Measured in Chrome 152: **0 frames in
three seconds before, 311 after.** If you build your own `ViewCollection`
instead of using this root, you will need to do the same thing.

Firefox does not have the problem. Measured the same way in 151 and 155: with a
pop-out open it keeps reporting the opener `visible` and runs it at full rate
(308 animation frames in 2.5s, against 9 for the same page with no pop-out), so
Flutter never switches frames off. The workaround is gated on frames actually
being disabled, so in Firefox it costs nothing and never runs.

## The keyboard works in there

Also not free. Flutter binds the keyboard once, to the page's own window, so a
pop-out is not on the path — `Shortcuts`, `Actions`, `Focus.onKeyEvent`,
Escape and Tab traversal receive nothing, while plain typing keeps working
because the browser routes characters to the focused element itself. This
package replays key and selection events into the opener and hands Flutter
focus to the pop-out's view when the window takes it.

## One window, browser-wide

A browser permits exactly one picture-in-picture window at a time, across every
tab. Opening a second closes the first, including one belonging to a different
site. `DocumentPip.current` is how you notice, and `window.closed` completes
when yours is displaced.

## Errors

```dart
try {
  await DocumentPip.open();
} on DocumentPipUnsupported {
  // Safari, Firefox for Android, or not the web at all.
} on DocumentPipNotBootstrapped {
  // The bootstrap above is missing. The message is the snippet.
} on DocumentPipDenied catch (e) {
  // The browser said no. Its own reason is in e.message — most often the
  // user-gesture rule, but an iframe gets refused too.
}
```

All three extend `DocumentPipException`, which is `sealed`, so a `switch` over
a failure is exhaustive and a new case is a compile error rather than a silent
fall-through.

## What this does not do

**Desktop Chromium and Firefox 151+.** Chrome and Edge have had Document
Picture-in-Picture since 116; Firefox shipped it in 151 on 2026-05-19. Safari
and Firefox for Android have no implementation, and neither does any non-web
platform. `DocumentPip.isSupported` is a feature detect, so it is true wherever
the API exists — gate the control on it rather than showing a button that
always fails.

**Both engines were verified for this release**, by running the example in
each: Chrome 152, and Firefox 151.0 and 155.0.1. In Firefox the pop-out opens
at exactly the size requested, Flutter adds its view inside the new document
and paints there, and the keyboard bridge replays keys into the opener
correctly. Safari and Firefox for Android have no implementation to test.

**Not video picture-in-picture.** If you want the OS video PiP that Android and
iOS have, this is the wrong package — on Android try `floating` or
`simple_pip_mode`; both are Android-only, and on iOS the system only offers PiP
for video playback, not arbitrary UI. This renders arbitrary widgets, and only
on the web.

**The window is the browser's, not yours.** It decides the real size, remembers
what the user resized it to, and can close it whenever it likes. Treat `width`
and `height` as a request.

**No nested pop-outs.** One window, browser-wide, is the platform's rule.

**Hot restart orphans the window.** Nothing here hooks hot restart, so after
one the browser's window is still on screen, frozen, while `current` reports
null. Close it by hand. Development only — a released app never hot restarts.

**The window renders at the page's pixel ratio.** Flutter's web engine keeps
one display object for the whole app, so dragging the pop-out onto a monitor
with a different density does not re-rasterise it, and no metrics event fires.
Not fixable from a package.

**Clipboard fails while the pop-out has focus.** Chrome rejects a clipboard
read from a document that is not focused, and the engine's clipboard is the
page's. Copy from the page, not from the window.

**Use a plain `Navigator` in `popOut`.** Route information travels on one
global channel that writes the page's history, so two `MaterialApp.router`s
will fight over the URL.

**Browser defaults still fire inside the pop-out.** The bridge asks the engine
whether Flutter consumed a key and mirrors that back, but measured against a
real `Shortcuts` handler the engine does not report consumption — the action
runs and the event stays un-prevented. So a shortcut you handle in Dart may
also do whatever the browser would have done. The pop-out is a real browser
window and this release does not suppress that; the behaviour is pinned by a
test, so if the engine changes it will be noticed rather than assumed.

**Replayed keys reach your page's own listeners too.** Keys are replayed into
the opener's `<body>` and bubble to `document` and `window`, so a page that
mixes Flutter with its own markup will see its global shortcuts fire for keys
typed in the pop-out. Scope those listeners to your own subtree.

**One console warning per window.** Chrome logs `ResizeObserver loop completed
with undelivered notifications` when a window opens. It comes from Flutter's
own observer on a newly added view host, not from this package — a
picture-in-picture window built with identical markup but no Flutter view logs
nothing. It means notifications were deferred a frame, not lost, and nothing
here can suppress it.

---

Not affiliated with Google or the Flutter team.
