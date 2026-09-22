# macos_grants example

A diagnostic panel: what this copy of the app is, what it is allowed to do, and
the sentence worth showing a user when a grant will not apply.

```sh
flutter run -d macos
```

The sandbox is off in `macos/Runner/*.entitlements`, on purpose — a sandboxed
app cannot reach the paths Full Disk Access protects, so every probe there
answers `unknown`. Your own app keeps whatever sandbox setting it needs.

To see the case the package exists for, break a copy of the built app:

```sh
cp -R build/macos/Build/Products/Debug/macos_grants_example.app /tmp/broken.app
printf '\n' >> /tmp/broken.app/Contents/Frameworks/FlutterMacOS.framework/Resources/Info.plist
/tmp/broken.app/Contents/MacOS/macos_grants_example
```

It reports `valid: false`, and the panel says reinstall rather than relaunch.
