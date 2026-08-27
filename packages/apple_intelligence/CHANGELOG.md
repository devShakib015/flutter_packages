## 0.1.0

Initial release: Apple Intelligence image generation for Flutter.

- `ImageCreator.generate` produces images on device with no UI, delivered as a
  `Stream` so the first can be shown while the rest are still being made.
  Cancelling the subscription cancels the work on the device.
- `ImagePlaygroundSheet.present` shows Apple's own generation UI and returns the
  file it wrote, or null if the user cancelled.
- `ImageCreator.availability` reports the sheet and streaming separately,
  because the sheet is iOS 18.1 and streaming is 18.4 — a device can offer one
  and not the other.
- `ImageConcept.text` names a subject; `ImageConcept.extractedFrom` asks the
  system to find the subjects in a passage.
- Errors arrive as a typed hierarchy — `OsTooOldException`,
  `GenerationUnavailableException`, `GenerationRefusedException` with a specific
  reason — never as a bare `PlatformException`.

Verified against real Apple Intelligence hardware: two PNGs of about 4 MB, the
first at 6.8s and the second at 10.3s.

**Not included:** Writing Tools and Genmoji. Both are planned; Writing Tools
attaches to a native text view while Flutter renders its own text, so it needs a
design decision rather than a wrapper.
