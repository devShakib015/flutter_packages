# macos_grants

macOS privacy grants from Flutter — and the question no other package asks:
**can this copy of your app hold a grant at all?**

macOS matches a privacy grant against your app's code signature. A bundle whose
nested code no longer matches its outer seal — an interrupted build, a
framework rewritten after signing — has no identity for macOS to match, so the
Full Disk Access switch can be on and your app stays blocked. Telling that user
to "relaunch and try again" is a loop with no exit.

```dart
final signing = await MacGrants.signing();
final access = await MacGrants.fullDiskAccess();

print(access.explain(signing));
// Access is turned off. Grant it in System Settings ▸ Privacy & Security.
// ...or, when the bundle no longer validates:
// This copy of the app has been modified since it was signed, so macOS
// cannot match a privacy grant to it. Reinstall it, then grant access again.
```

## What it reads

| Call | Answers | How |
| --- | --- | --- |
| `MacGrants.signing()` | `valid`, `identity`, `teamId`, `survivesUpdate` | `SecStaticCodeCheckValidity` with nested-code and strict flags |
| `MacGrants.fullDiskAccess()` | `granted` · `denied` · `unknown` | opens paths the grant protects — macOS offers no API for this one |
| `MacGrants.accessibility()` | `granted` · `denied` · `unknown` | `AXIsProcessTrusted` |
| `MacGrants.screenRecording()` | `granted` · `denied` · `unknown` | `CGPreflightScreenCaptureAccess`; 10.14 had no such grant, so `granted` there |
| `MacGrants.openSettings(pane)` | opened or not | the Settings anchor for that pane |

```dart
final s = await MacGrants.signing();
s.valid           // false: modified since it was signed — no grant can apply
s.identity        // developerId · appStore · adHoc · unsigned · unknown
s.survivesUpdate  // false for ad-hoc: every build is a new app to macOS
```

`survivesUpdate` is the other honest answer. An ad-hoc signature (`codesign -s -`,
what you get without a $99 Developer ID) makes the code's own hash its identity,
so **every update loses the grant** and the user has to give it again. No release
script fixes that, and an app that knows can say so in its release notes instead
of letting people find out.

## Nothing here prompts

macOS shows no prompt for Full Disk Access, and none of these grants can be
requested from code. The most any app can do is report the truth and open the
right pane:

```dart
if (await MacGrants.fullDiskAccess() != GrantStatus.granted) {
  await MacGrants.openSettings(PrivacyPane.fullDiskAccess);
}
```

## What it will not do

- **It never guesses.** A check that cannot run answers `unknown`, and
  `signing()` answers `valid: true`. Telling someone their working app is
  broken is worse than saying nothing.
- **A sandboxed app gets `unknown` for Full Disk Access.** The sandbox blocks
  the probe paths themselves, so there is nothing to learn from them. That is
  reported as unknown rather than denied.
- **Off macOS, the web included, everything answers `unknown`** and
  `openSettings` returns false, so cross-platform code does not need a guard on
  every line.
- **`signing()` hashes your bundle**, which for a large app is tens of
  milliseconds to a second. It runs off the main thread natively, but call it
  when something is wrong, not every frame.

## Probe paths

Full Disk Access is read by opening the things it protects: the TCC databases,
`~/Library/Safari`, `~/Library/Mail`, `~/Library/Messages`, cookies, the address
book. Every path is tried, because a Mac may legitimately have none of Mail,
Safari or Messages, and one readable path proves the grant. A path that exists
and refuses proves the opposite; nothing found at all is `unknown`, never
`denied`. They are exposed as `kFullDiskAccessProbes`, and `readFullDiskAccess`
takes a `ProbeFileSystem` so the decision is testable without a Mac.

## Requirements

macOS 10.14+. No entitlements, no configuration. The plugin links only
Security, ApplicationServices and CoreGraphics, all of which ship with macOS,
so adding it does not raise your deployment target. It builds through Swift
Package Manager or CocoaPods, whichever your app uses.

## Why this exists

I shipped a Mac app that read protected folders, a user turned Full Disk Access
on, and it stayed blocked. The bundle had been sealed by one build and its
`App.framework` written by a later one, so macOS had nothing to match the grant
to — and the app kept telling them to relaunch.
[The whole story is here](https://devshakib.jumyn.com/blog/full-disk-access-was-on-and-macos-still-refused-the-app).

MIT licensed. Issues and pull requests:
[devShakib015/flutter_packages](https://github.com/devShakib015/flutter_packages).
