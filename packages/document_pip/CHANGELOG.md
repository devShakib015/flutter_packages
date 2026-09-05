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

### Audited before release

The lifecycle was driven in a real browser rather than reasoned about, and the
public surface read against it. Three defects found and fixed before anyone
could hit them:

- **A view was only *guessed* to be a pop-out.** `DocumentPipApp` took the
  lowest view id to be the page, which is wrong for any app with more than one
  page-level view — add-to-app, or several Flutter hosts on one page. Every
  host but the lowest would have rendered the pop-out into the main area. The
  package now tracks the views it opened and `DocumentPip.popOutViewIds`
  exposes them, so nothing is inferred.
- **A closed window was retained.** The static holding the current window was
  never cleared, keeping a dead `Window` and its whole document alive.
- **A stylesheet `<link>` was cloned, not adopted.** `cloneNode` leaves the node
  owned by the source document; `importNode` is what the DOM spec asks for
  across documents.

Confirmed sound by driving it: `pagehide` does fire when the user closes the
window, so `closed` completes and the view is removed; calling `close()` twice
is safe; and a second `open()` correctly displaces the first, completes its
`closed`, and drops it from the tracked set.

Known and not ours: Chrome logs one `ResizeObserver loop completed with
undelivered notifications` per window. Attributed by controlled test — a
picture-in-picture window with identical markup but no Flutter view logs
nothing, so it is Flutter's observer on the new host.

Verified end to end in Chrome 152 rather than assumed: a real click dispatched
through the browser's input pipeline opens the window, and a Flutter view is
confirmed rendering inside its document. Eleven tests on the VM plus four in a
real browser via `flutter test --platform chrome`.
