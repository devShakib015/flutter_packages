/// Live Flutter widgets in a real, always-on-top operating-system window,
/// from Flutter Web.
///
/// Not a widget floating inside your app: an actual window the browser owns,
/// which stays above every other application while your app keeps running.
///
/// ```dart
/// void main() => runWidget(
///       DocumentPipApp(
///         main: (context) => const MaterialApp(home: Player()),
///         popOut: (context) => const MaterialApp(home: MiniPlayer()),
///       ),
///     );
///
/// // ...in a button handler, before any other await:
/// final window = await DocumentPip.open(width: 380, height: 240);
/// ```
///
/// Two things this needs that an ordinary package does not, both because
/// multi-view is a property of how the engine starts:
///
///  * `runWidget`, not `runApp`.
///  * A bootstrap that switches multi-view on and hands over the app runner.
///    `DocumentPipNotBootstrapped` carries the exact snippet.
///
/// Chromium only. Everywhere else `DocumentPip.isSupported` is false.
library;

export 'src/document_pip.dart' show DocumentPip;
export 'src/document_pip_app.dart' show DocumentPipApp;
export 'src/exceptions.dart'
    show
        DocumentPipDenied,
        DocumentPipException,
        DocumentPipNotBootstrapped,
        DocumentPipUnsupported;
export 'src/pip_window.dart' show PipWindow;
