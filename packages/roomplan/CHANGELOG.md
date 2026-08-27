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
