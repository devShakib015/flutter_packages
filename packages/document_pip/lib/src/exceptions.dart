/// Something went wrong opening or using a picture-in-picture window.
///
/// Sealed, so a `switch` over a failure is exhaustive and adding a case later
/// is a compile error rather than a silent fall-through.
sealed class DocumentPipException implements Exception {
  /// Creates the exception.
  const DocumentPipException(this.message);

  /// What went wrong, and where possible what to do about it.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The browser cannot do this.
///
/// Chrome and Edge have had Document Picture-in-Picture since 116 and Firefox
/// since 151; Safari, Firefox for Android and every non-web platform have no
/// implementation. Check `DocumentPip.isSupported` and offer something else.
class DocumentPipUnsupported extends DocumentPipException {
  /// Creates the exception.
  const DocumentPipUnsupported([
    super.message =
        'Document Picture-in-Picture is not available here. Chrome and Edge '
        'have had it since 116 and Firefox since 151; Safari, Firefox for '
        'Android and every non-web platform do not. Gate on '
        'DocumentPip.isSupported.',
  ]);
}

/// The browser refused to open the window.
///
/// Almost always the missing user gesture: `requestWindow` may only be called
/// while handling a real click, tap or key press. Awaiting anything before
/// calling it spends the gesture, so open the window first and do the slow
/// work afterwards.
class DocumentPipDenied extends DocumentPipException {
  /// Creates the exception.
  const DocumentPipDenied(super.message);
}

/// The app never handed its Flutter app runner over.
///
/// A package cannot add a Flutter view on its own: `dart:ui_web` exposes the
/// views read-only, and only the JS app object returned by `engine.runApp()`
/// can add one. That object lives in your bootstrap, so your bootstrap has to
/// pass it along. The message carries the exact snippet.
class DocumentPipNotBootstrapped extends DocumentPipException {
  /// Creates the exception.
  const DocumentPipNotBootstrapped([
    super.message = '''
document_pip could not find your Flutter app runner.

Multi-view has to be switched on in the bootstrap, and the runner handed over,
because only it can add a view. Put this in web/flutter_bootstrap.js:

  {{flutter_js}}
  {{flutter_build_config}}

  _flutter.loader.load({
    config: { multiViewEnabled: true },
    onEntrypointLoaded: async function (engineInitializer) {
      const engine = await engineInitializer.initializeEngine({
        multiViewEnabled: true,
      });
      const app = await engine.runApp();
      window.documentPipApp = app;              // <- document_pip needs this
      app.addView({ hostElement: document.querySelector('#app') });
    },
  });

In multi-view mode no view is created for you, which is why the page's own
view is added explicitly on the last line. Give web/index.html a host for it
to point at -- Flutter sizes a view to 100% of its host and CLEARS that host's
children, so never pass document.body:

  <body style="margin:0;height:100%">
    <div id="app" style="position:absolute;inset:0"></div>
  </body>

Then use runWidget(), not runApp().''',
  ]);
}
