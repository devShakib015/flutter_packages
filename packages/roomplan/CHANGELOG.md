## 0.3.1

No code changes. This release exists because the package was almost impossible
to install.

`sdk: ^3.13.0` meant Dart 3.13, which only ships with **Flutter 3.47** —
released three weeks ago. Anyone on an older SDK hit a version-solve failure
before they could try it. The floor is now `^3.5.0` / Flutter 3.24, and it is
tested: the library resolves and type-checks against Flutter 3.16.9 / Dart
3.2.6, so the declared range is narrower than the verified one.

## 0.3.0

An audit of every package in this repo found five defects here, including one
that crashed the host app on the first scan.

### Fixed

- **Starting a scan terminated the app.** RoomPlan uses the camera, and iOS
  kills a process that touches it without `NSCameraUsageDescription` — not a
  permission dialog, a crash. The key was absent from the example and
  undocumented in the README. Both fixed, with a Setup section that says the
  host app must declare it.
- **`import 'dart:io'` made the package impossible to compile for web,** while
  the `kIsWeb` guards claimed it was safe there. Replaced with
  `defaultTargetPlatform`, which also lets a widget test drive the fallback.
- **An iPhone without LiDAR got a black rectangle instead of `fallback`.** The
  view checked the platform but never the device, so it built a `UiKitView`
  RoomPlan could not fill — contradicting its own dartdoc. It asks
  `RoomScanController.support()` now and shows `fallback` when the answer is
  no.
- **A second scan silently did nothing.** RoomPlan ends the session itself when
  the user finishes, and nothing cleared the native `isRunning` flag on that
  path — so the next Start hit its guard and returned success without starting
  anything. Cleared in both delegate callbacks.
- **A floor plan never redrew when its style changed.** `FloorPlanStyle` had
  identity equality, so `shouldRepaint` could not see a difference and a theme
  switch changed nothing on screen. It compares by value now.

### Still true

A real scan remains unverified — it needs LiDAR hardware this project does not
have. That has been in the README since 0.1.0 and still is.

## 0.2.0

- `RoomFloorPlan` draws a scan as a top-down floor plan: walls, doors, windows
  and openings in their own colours, furniture as correctly rotated footprints,
  scaled to fit whatever box it is given. A `CapturedRoom` is transforms and
  extents in metres — useful, but not something a person can look at, and
  turning it into a picture involves enough column-major arithmetic to be worth
  doing once here rather than in every app.
- `FloorPlanStyle` for colours and stroke weights.

The README now has a picture, drawn from the sample room in the test suite. It
is still not a photograph of a real scan, because that needs LiDAR hardware
this package has not been run on — and that remains stated plainly.

## 0.1.0

Initial release: Apple RoomPlan for Flutter.

- `RoomScanView` hosts Apple's own `RoomCaptureView`, including its live
  coaching overlay and wireframe, as a platform view.
- `RoomScanController` starts and stops a scan and delivers the finished room
  on a stream, because RoomPlan post-processes after the scan ends rather than
  returning immediately.
- `CapturedRoom` gives walls, floors, doors, windows, openings and recognised
  objects, with metre dimensions and positions read out of their transforms —
  plus `raw`, RoomPlan's own encoding kept whole.
- A USDZ model is exported for each scan, ready for AR Quick Look.
- `RoomScanController.support()` distinguishes "no LiDAR" from "iOS too old",
  since those need different things said to a user.

**Not yet verified on a LiDAR device.** The plugin builds, registers, and
reports `noLidar` correctly where the sensor is absent, but no real scan has
been observed end to end. The typed model is unit tested against realistic JSON
and is deliberately forgiving; `raw` is always the whole encoding. The README
says this too.
