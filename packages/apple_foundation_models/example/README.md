# apple_foundation_models example

Exercises every capability against the real on-device model: availability
reporting, plain and streaming responses, schema-constrained structured output,
and tool calling back into Dart.

```bash
flutter run -d macos
```

Needs macOS 26 (or iOS 26) on Apple Intelligence hardware with the feature
enabled. Without it the app still runs and shows why the model is unavailable —
which is the state most users will be in, and worth seeing.

The integration tests in `integration_test/` run the same paths headlessly:

```bash
flutter test integration_test/plugin_test.dart -d macos
```
