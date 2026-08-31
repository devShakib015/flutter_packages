// Picks the implementation for the platform being compiled for.
//
// Off the web there is exactly one instance of the app, so the stub behaves
// like a single tab that is always the leader. That is not a degraded mode —
// it is the correct answer, and it means cross-platform code needs no branch.
export 'stub_impl.dart' if (dart.library.js_interop) 'web_impl.dart';
