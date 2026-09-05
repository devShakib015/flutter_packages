import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// `window.documentPictureInPicture`.
///
/// Hand-bound because `package:web` does not ship the Document
/// Picture-in-Picture API: it is Chromium-only and not in the WebIDL that
/// package is generated from.
@JS('documentPictureInPicture')
external DocumentPictureInPicture? get documentPictureInPicture;

/// The entry point for opening a picture-in-picture window.
extension type DocumentPictureInPicture._(JSObject _) implements JSObject {
  /// Opens the window. Requires a live user gesture.
  external JSPromise<web.Window> requestWindow([PipOptions options]);

  /// The open window, or null. At most one exists per browser.
  external web.Window? get window;
}

/// Options for [DocumentPictureInPicture.requestWindow].
extension type PipOptions._(JSObject _) implements JSObject {
  /// Creates the options object.
  external factory PipOptions({
    int? width,
    int? height,
    bool? disallowReturnToOpener,
    bool? preferInitialWindowPlacement,
  });
}

/// The Flutter engine's JS app object, as returned by `engine.runApp()`.
///
/// This is the only thing that can add a view, and `dart:ui_web` exposes the
/// view manager read-only, so the app has to pass it over on a global. See
/// `DocumentPipNotBootstrapped` for the snippet.
extension type FlutterAppRunner._(JSObject _) implements JSObject {
  /// Adds a Flutter view rendering into `hostElement` and returns its id.
  external int addView(AddViewOptions options);

  /// Removes the view with this id.
  external JSObject? removeView(int viewId);
}

/// Options for [FlutterAppRunner.addView].
extension type AddViewOptions._(JSObject _) implements JSObject {
  /// Creates the options object.
  external factory AddViewOptions(
      {web.Element hostElement, JSAny? initialData});
}

/// Where the app is expected to leave its runner.
@JS('documentPipApp')
external FlutterAppRunner? get documentPipApp;
