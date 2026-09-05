## 0.1.0

First release.

Live Flutter widgets in a real, always-on-top operating-system window, from
Flutter Web — an actual window the browser owns, not a widget floating inside
your app.

- `DocumentPip.open()` opens the window and renders a Flutter view into it,
  with `isSupported`, `current`, and a `PipWindow` handle carrying `viewId`,
  `isOpen`, `close()` and a `closed` future that completes however the window
  went away, including when the browser displaces it for someone else's.
- `DocumentPipApp` is the `runWidget` root: it owns the `ViewCollection`, works
  out which view is the page and which are windows, and rebuilds when the set
  changes. State lifted above it is shared between windows.
- A sealed `DocumentPipException`: `DocumentPipUnsupported`,
  `DocumentPipDenied` and `DocumentPipNotBootstrapped`. The last one carries
  the bootstrap snippet verbatim, because a package cannot switch multi-view on
  from the inside and the symptom does not suggest the fix.
- Copies the opener's stylesheets into the new document, which starts with
  none. Cross-origin sheets throw on `cssRules`, so their `<link>` is cloned
  instead and a Google Fonts face still applies.
- Compiles everywhere through a conditional export; off the web `isSupported`
  is false and `open()` throws rather than failing to build.

Chromium only — Firefox and Safari have no implementation.

Verified end to end in Chrome 152 rather than assumed: a real click dispatched
through the browser's input pipeline opens the window, and a Flutter view is
confirmed rendering inside its document. Eleven tests on the VM plus four in a
real browser via `flutter test --platform chrome`.
