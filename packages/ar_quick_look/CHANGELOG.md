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
