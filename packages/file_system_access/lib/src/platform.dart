// Picks the implementation for the platform being compiled for.
//
// Off the web there is no File System Access API at all, so the stub reports
// everything unsupported rather than failing to compile. That keeps the
// package addable to an app that also targets mobile and desktop.
export 'stub_impl.dart' if (dart.library.js_interop) 'web_impl.dart';
