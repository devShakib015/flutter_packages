# document_pip

Live Flutter widgets in a real, always-on-top operating-system window — from
Flutter Web.

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

Forget either and `DocumentPip.open()` throws `DocumentPipNotBootstrapped`,
whose message is this snippet.

## Install

```bash
flutter pub add document_pip
```

## Opening the window

```dart
if (!DocumentPip.isSupported) return;   // Chromium only — see below

final window = await DocumentPip.open(
  width: 380,
  height: 210,
  copyStyles: true,             // the new document starts with none
  disallowReturnToOpener: false,
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

Get that wrong and you get `DocumentPipDenied`, whose message says so — the
underlying `NotAllowedError` does not.

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
  // Firefox, Safari, or not the web at all.
} on DocumentPipNotBootstrapped {
  // The bootstrap above is missing. The message is the snippet.
} on DocumentPipDenied catch (e) {
  // Almost always the user-gesture rule.
}
```

All three extend `DocumentPipException`, which is `sealed`, so a `switch` over
a failure is exhaustive and a new case is a compile error rather than a silent
fall-through.

## What this does not do

**Chromium only.** Document Picture-in-Picture is a Chrome and Edge feature.
Firefox and Safari have no implementation and none is announced.
`DocumentPip.isSupported` is false there, and on every non-web platform, so
gate the control on it rather than showing a button that always fails.

**Not video picture-in-picture.** If you want the OS video PiP that Android and
iOS have, this is the wrong package — try `floating` or `simple_pip_mode`. This
renders arbitrary widgets, and only on the web.

**The window is the browser's, not yours.** It decides the real size, remembers
what the user resized it to, and can close it whenever it likes. Treat `width`
and `height` as a request.

**No nested pop-outs.** One window, browser-wide, is the platform's rule.

---

Not affiliated with Google or the Flutter team.
