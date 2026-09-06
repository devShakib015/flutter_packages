# document_pip example

A player whose mini view pops out into a real, always-on-top browser window.

The point of the demo is the shared state. `_Playback` sits **above**
`DocumentPipApp`, so the page and the floating window read the same object —
scrub in one and the other moves, because there is only one.

## Running it

```bash
flutter run -d chrome
```

Chrome, Edge, or Firefox 151+. The button disables itself elsewhere.

## The part that is not boilerplate

`web/flutter_bootstrap.js` and `web/index.html` are **hand-written and
load-bearing**, not generated scaffolding. Do not let `flutter create`
regenerate them:

- `flutter_bootstrap.js` switches multi-view on and puts the app runner on
  `window.documentPipApp`. Only that object can add a Flutter view, and
  `dart:ui_web` exposes the view manager read-only — so a package cannot do
  this for you.
- `index.html` provides the sized `<div id="app">` the bootstrap points at.
  Flutter clears a host element's children and sizes the view to 100% of it,
  so hosting on a bare `<body>` would wipe the page and then render nothing.

Both files are reproduced in the package README, and `DocumentPip.open()`
throws with the same snippet if the handover is missing.

## Where to look

`lib/main.dart` — `DocumentPipApp` takes `main:` and `popOut:` builders, and
`_popOut()` shows the one rule that matters: `DocumentPip.open()` must be the
first `await` in the gesture handler, or the browser refuses.
