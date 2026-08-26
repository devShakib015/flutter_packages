# devShakib Flutter packages

Open-source Flutter packages published to pub.dev. A Dart pub workspace — one
lockfile, one `.dart_tool`, members resolved by path.

| Package | Description |
| --- | --- |
| [loading_kit](packages/loading_kit) | A blocking-async overlay that never flickers |
| [apple_foundation_models](packages/apple_foundation_models) | Run Apple's on-device language model from Flutter |

```bash
flutter pub get
cd packages/loading_kit && flutter test
```

`apple_foundation_models` also carries integration tests that run against the
real on-device model. They need Apple Intelligence hardware on macOS 26:

```bash
cd packages/apple_foundation_models/example
flutter test integration_test/plugin_test.dart -d macos
```

MIT © K M Shahriar Hossain
