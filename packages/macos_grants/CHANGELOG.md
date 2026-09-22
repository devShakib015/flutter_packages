## 0.1.1

- **Builds with Swift Package Manager.** `Package.swift` depended on a package
  called `FlutterMacOS`, which Flutter never generates, so dependency
  resolution failed before any Swift was compiled — in every app using Swift
  Package Manager, Flutter's default. It now depends on `FlutterFramework`,
  like Flutter's own plugin template.
- **Compiles on macOS 10.14, as declared.** `screenRecording()` called
  `CGPreflightScreenCaptureAccess`, a macOS 10.15 API, with no availability
  check, so an app targeting 10.14 could not compile the plugin. On 10.14 it
  now answers `granted`: Screen Recording was not a grant before 10.15, and
  every app could capture the screen.
- **Off macOS includes the web.** `isMacOS` read `Platform.isMacOS`, which
  throws on the web instead of answering false, so every call threw there
  rather than answering `unknown`.
- The example's entitlements, which turn the sandbox off so the Full Disk
  Access probes can run, now ship with it. They had been ignored along with
  the generated `macos/` folder, so a fresh copy of the example ran sandboxed
  and answered `unknown`.
- Tests no longer ship in the package, and the screenshot's description fits
  pub.dev's 160-character limit, which it overran and was marked down for.

## 0.1.0

First release.

- **`MacGrants.signing()`** — whether this bundle still validates (nested code
  included), who signed it, and whether a grant given to it survives an update.
  An ad-hoc signature makes the code's hash its identity, so every build is a
  new app to macOS.
- **`MacGrants.fullDiskAccess()`** — read by opening the paths the grant
  protects, since macOS offers no API for it. Every probe is tried; a path that
  exists and refuses means denied, nothing found at all means unknown.
- **`MacGrants.accessibility()`** and **`MacGrants.screenRecording()`**.
- **`MacGrants.openSettings(pane)`** for the six Privacy panes, because none of
  these grants can be requested from code.
- **`GrantStatus.explain(signing)`** — the sentence to show a user, including
  the one case where "relaunch" never works and "reinstall" is the answer.

Every failure answers `unknown`, and a signature check that cannot run answers
valid: a check that did not happen must not accuse a working app.
