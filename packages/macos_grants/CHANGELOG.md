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
