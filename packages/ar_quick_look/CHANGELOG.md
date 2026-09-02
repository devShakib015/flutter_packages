## 0.2.0

An audit of every package in this repo found three defects here, one of which
served the wrong model.

### Added

- `AlreadyPresentingException`, and `refresh` on `materializeAsset`.

### Fixed

- **Two assets with the same filename served each other's bytes.** The cached
  copy was keyed on the *basename*, so `assets/chairs/model.usdz` and
  `assets/tables/model.usdz` wrote to one path — and since the cache check was
  only "exists and non-empty", whichever landed first was shown for both. The
  copy is namespaced by the whole asset key now, and still ends in `.usdz` so
  Quick Look sniffs it correctly.
- **A second `present()` blanked the first viewer and stranded its future.**
  The new session replaced the old one, which deallocated it — and the
  controller holds its data source weakly, so the open viewer went empty while
  the first `await` never returned. There is one screen, so a second present
  is now refused with `AlreadyPresentingException`.
- **Only the first file's format was checked.** `presentAll` existence-checks
  every path and the controller opens on `initialIndex`, so a bad model
  anywhere but position zero sailed past the precheck and failed inside Quick
  Look instead. Every item is checked, and the message names the offender.
- **A missing asset key threw a raw `FlutterError`,** escaping the sealed
  exception hierarchy — the commonest setup mistake this package has was not
  catchable as one of its own. It is a `FileNotFoundException` naming the
  pubspec now.
- An interrupted copy is no longer cached: the write goes to a `.part` file and
  is renamed into place.

## 0.1.0

Initial release: Apple's AR Quick Look for Flutter.

- `ArQuickLook.present` shows a USDZ or Reality file in the system viewer, and
  completes when the user closes it rather than when it opens.
- `canPreview` asks Quick Look whether it will actually read a file, so a
  wrong-format file with the right extension is refused before a viewer is put
  on screen.
- `presentAsset` copies a bundled asset out to a real file first, because Quick
  Look needs a path and a Flutter asset is not one. The copy is cached;
  `materializeAsset` is public for anything else that needs a path.
- `allowsContentScaling: false` for models whose size is the point, and
  `canonicalWebPage` for where Quick Look's Share button should lead.
- `presentAll` for several models the user can page between.
- Errors are a sealed hierarchy, never a bare `PlatformException`.

Pairs with [roomplan](https://pub.dev/packages/roomplan): the USDZ it exports
goes straight into `present`.

Verified on a Simulator — registration, support, and every error path,
including a text file renamed `.usdz` being refused. The AR camera experience
itself needs a real device.
