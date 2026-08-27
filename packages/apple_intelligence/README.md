# apple_intelligence

Generate images on device with Apple Intelligence, from Flutter.

```dart
await for (final image in ImageCreator.generate(
  concepts: [ImageConcept.text('a fox reading a map by lantern light')],
  style: ImageStyle.illustration,
  limit: 4,
)) {
  setState(() => images.add(image.bytes)); // shows each one as it lands
}
```

## Why this exists

`apple_foundation_models` gave Flutter Apple's on-device *language* model. This
is the other half. At the time of writing there is no Flutter binding for Apple
Intelligence image generation at all — a pub.dev search for Image Playground
returns nothing.

## Streaming is the point

The obvious binding here is the Image Playground sheet: present Apple's modal,
get a file back. That is included, and it is the right thing on devices a few
point-releases behind. But `ImageCreator` generates with **no UI at all** and
hands images back one at a time, so you can show the first while the rest are
still being made.

Measured on real hardware, four images at `illustration` style:

| | |
| --- | --- |
| first image | 6.8s |
| second image | 10.3s |
| size | ~4 MB PNG each |

Those numbers are why this is a `Stream` and not a `Future<List>`. Cancelling
the subscription cancels the work on the device.

## Ask before you assume

Three separate questions, because the answers genuinely differ:

```dart
final a = await ImageCreator.availability();
a.status;   // available | unavailable | osTooOld
a.sheet;    // the Image Playground sheet — iOS 18.1+
a.creator;  // streaming, no UI       — iOS 18.4+
```

The sheet arrived in iOS 18.1 and streaming in 18.4, so a device can perfectly
well offer one and refuse the other. Styles are 18.4 too, which is why setting
one on an 18.1 device is quietly ignored rather than crashing.

## Errors say which kind of no

```dart
try {
  await ImageCreator.generate(concepts: [...]).drain();
} on GenerationRefusedException catch (e) {
  // e.reason: unsupportedLanguage, faceTooSmall, backgroundForbidden, …
} on GenerationUnavailableException {
  // Apple Intelligence is off, or still downloading
} on OsTooOldException {
  // this OS never had it
}
```

Nothing throws a bare `PlatformException`. "This device cannot" and "this prompt
was refused" are different problems and want different handling, so they are
different types.

One worth knowing about: **Apple refuses image creation to an app that is not
frontmost**, and reports it as `backgroundForbidden`. That is a product rule,
not a bug — it also means an integration test cannot verify generation, since
the harness cannot foreground the app.

## The sheet

```dart
final path = await ImagePlaygroundSheet.present(
  concepts: [ImageConcept.text('a fox reading a map')],
  style: ImageStyle.sketch,
);  // null if the user cancelled
```

## Concepts

`ImageConcept.text('…')` names a subject. `ImageConcept.extractedFrom(prose)`
asks the system to find the subjects in a passage itself, which is what makes
illustrating a note or a message thread practical.

## Not in this version

**Writing Tools and Genmoji are not here yet.** Both are real Apple Intelligence
surfaces with no Flutter binding, and both are planned, but Writing Tools
attaches to a native text view and Flutter renders its own text — so it needs a
design decision rather than a wrapper, and shipping a half-working one would be
worse than shipping none.

## Requirements

iOS 18.1+ / macOS 15.1+ for the sheet, iOS 18.4+ / macOS 15.4+ for streaming,
on Apple Intelligence hardware with the models downloaded. The plugin compiles
into apps targeting far older systems and reports `osTooOld` there, so adding it
does not raise your deployment target.

## License

MIT © K M Shahriar Hossain
