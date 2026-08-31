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
