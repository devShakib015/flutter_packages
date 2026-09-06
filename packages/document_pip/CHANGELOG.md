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
  none — along with the `class`, `dir`, `lang` and `data-*` attributes those
  stylesheets select on, so a themed app looks the same in the window. A
  cross-origin sheet throws on `cssRules`, so its `<link>` is adopted with
  `importNode` and a Google Fonts face still applies.
- `preferInitialWindowPlacement` asks for the size you passed rather than the
  one the user last left a window at.
- Compiles everywhere through a conditional export; off the web `isSupported`
  is false and `open()` throws rather than failing to build.

Chromium only — Firefox and Safari have no implementation.

### Audited before release

The lifecycle was driven in a real browser rather than reasoned about, and the
public surface read against it. Nine defects found and fixed before anyone
could hit them. The first two are the ones that mattered.

- **The pop-out froze the moment you switched tabs** — the one situation the
  window exists for. Chromium keeps painting a picture-in-picture opener at
  full rate while its tab is in the background, but still reports the page
  `hidden`; Flutter believes the report and turns frames off, after which
  `scheduleFrame()` returns early forever. Measured rather than argued: with a
  pop-out open, a backgrounded tab ran 302 animation frames in 2.5s against 2
  for the same page with none — and the example app went from **0 Flutter
  frames in 3 seconds to 311**. `DocumentPipApp` now keeps the pipeline turning
  with `scheduleForcedFrame` for exactly as long as the page is hidden and a
  window is open.
- **The keyboard was dead in the pop-out.** Flutter's `KeyboardBinding` is a
  singleton bound to the *opener's* `window`, so a separate browsing context is
  simply not on the propagation path: `Shortcuts`, `Actions`,
  `Focus.onKeyEvent`, `HardwareKeyboard`, Escape and Tab traversal all received
  nothing. Typing worked, because the browser routes characters to the focused
  DOM element natively, which is what made this easy to miss. Key and selection
  events are now replayed into the opener, and the pop-out's view is given
  Flutter focus when its window takes it — otherwise the keys arrive and drive
  the wrong window.
- **A resize rebuilt both windows, at frame rate.** `didChangeMetrics` fires on
  every frame of a drag and the rebuild was unconditional, so dragging either
  window re-ran both builders continuously. The example hid it by returning
  `const` widgets. Now it rebuilds on the view set changing, which is the only
  thing the build actually reads.
- **The `resize` listener was never removed**, keeping the host element alive
  after the window went.
- **Every refusal was reported as the user-gesture rule.** Chrome refuses for
  three reasons and reports all of them as `NotAllowedError`; the common one
  that is *not* the gesture is running inside an iframe, and those authors were
  being sent to fix a click handler that was already correct. The message now
  lists the causes instead of asserting one.
- **`copyStyles` copied the CSS but not what it selects on.** No `class`,
  `dir`, `lang` or `data-*` reached the new document, so `html.dark .card {}`
  matched nothing. The layout reset also overwrote any inline style rather than
  merging with it.
- **The browser tests had never run.** CI called bare `flutter test`, which
  never executes an `@TestOn('browser')` file — green CI that proved less than
  it looked like, here and in two other packages. It now runs
  `--platform chrome` wherever such a test exists.
- Three doc comments contradicted the code, including one still describing the
  lowest-view-id inference that the first audit had already deleted.

And from the first pass:

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
through the browser's input pipeline opens the window, a Flutter view is
confirmed rendering inside its document, and the whole app was then backgrounded
to measure whether it kept drawing. Seventeen tests on the VM plus twenty-three
in a real browser via `flutter test --platform chrome` — including one that
asserts the keyboard defect still exists without the bridge, so the workaround
can be deleted the day Flutter fixes it upstream.
