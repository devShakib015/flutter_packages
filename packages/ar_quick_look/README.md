# ar_quick_look

Show a 3D model in the room, using Apple's own viewer.

```dart
await ArQuickLook.present('/path/to/chair.usdz');
```

The future completes when the user closes the viewer, so `await` covers the
whole interaction rather than just opening it.

## Why the system viewer

AR Quick Look already handles placement, scaling, occlusion, contact shadows,
the object/AR toggle and sharing — tuned by Apple, and familiar to users from
Messages and Safari. Rebuilding that in Flutter would mean rebuilding an
interface people already know, worse.

So this presents theirs, and gets out of the way.

## Pairs with roomplan

[`roomplan`](https://pub.dev/packages/roomplan) exports a USDZ of a scanned
room and hands you the path. That path goes straight in here:

```dart
controller.rooms.listen((room) async {
  if (room.usdzPath != null) await ArQuickLook.present(room.usdzPath!);
});
```

Scan a room, then walk back into it.

## Ask before you offer it

```dart
if (!ArQuickLook.isSupported) return;              // iOS only
if (!await ArQuickLook.canPreview(path)) return;   // this file specifically
```

Two questions, because they fail differently. `canPreview` asks Quick Look
rather than looking at the extension, so a text file renamed `.usdz` comes back
false — which is what you want before presenting a viewer that would then fail.

## Bundled models

Quick Look needs a real file, and a Flutter asset is not one: it lives inside
the app bundle behind the asset system. This is the step everyone hits and
nobody expects, so it is handled:

```dart
await ArQuickLook.presentAsset('assets/models/chair.usdz');
```

The copy is cached, so showing the same asset twice writes it once.
`materializeAsset` is public for when something else needs a path — sharing a
model, or handing it to another app.

## Scaling

```dart
await ArQuickLook.present(path, allowsContentScaling: false);
```

Turn scaling off when the size is the point. A sofa the user can pinch to
half-size is no longer telling them whether it fits.

## Several models

```dart
await ArQuickLook.presentAll(paths, initialIndex: 2);
```

## Errors say which kind of no

`NotOnThisPlatformException`, `FileNotFoundException`,
`UnsupportedFileException`, `NoHostException` — a sealed hierarchy, so a
`switch` over them is exhaustive and nothing arrives as a bare
`PlatformException`.

## What is verified

The AR camera experience needs a real device. What runs on a Simulator, and is
tested there: the plugin registers, `isSupported` is true on iOS, a missing
file and an unreadable one each raise their own exception, and a text file
renamed `.usdz` is correctly refused.

## License

MIT © K M Shahriar Hossain
