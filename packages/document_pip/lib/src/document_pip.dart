import 'pip_window.dart';
import 'stub_impl.dart' if (dart.library.js_interop) 'web_impl.dart';

/// Opens a real, always-on-top operating-system window and renders live
/// Flutter widgets into it.
///
/// Not a widget floating inside your app — an actual window, owned by the
/// browser, that stays above every other application while your app keeps
/// running with its state intact.
///
/// ```dart
/// if (DocumentPip.isSupported) {
///   // Call this FIRST in the handler: awaiting anything before it spends the
///   // user gesture and the browser will refuse.
///   final window = await DocumentPip.open(width: 380, height: 260);
///   await window.closed;
/// }
/// ```
///
/// Rendering into the window is `DocumentPipApp`'s job; this only opens it.
///
/// Chromium only. Firefox and Safari have no implementation, and neither does
/// any non-web platform, so [isSupported] is false there and [open] throws
/// `DocumentPipUnsupported` rather than pretending.
abstract final class DocumentPip {
  /// Whether this browser can open one.
  ///
  /// False off the web and in Firefox and Safari. Check it before offering the
  /// control at all — a button that always errors is worse than no button.
  static bool get isSupported => DocumentPipImpl.isSupported;

  /// The window currently open, or null.
  ///
  /// A browser allows exactly one at a time, across every tab, so opening a
  /// second one closes the first — and this is how you notice.
  static PipWindow? get current => DocumentPipImpl.current;

  /// The Flutter views this package opened, by id.
  ///
  /// `DocumentPipApp` uses this to tell a pop-out from the page. Reach for it
  /// directly only if you are building your own `ViewCollection` — and prefer
  /// it to comparing view ids, because an app may add page-level views of its
  /// own and any ordering assumption breaks the moment it does.
  static Set<int> get popOutViewIds => DocumentPipImpl.popOutViewIds;

  /// Opens the window.
  ///
  /// Must be called while handling a real user gesture — a click, a tap, a key
  /// press — and must be the *first* await in that handler. Loading data and
  /// then opening will fail, because the gesture is spent by the time the
  /// browser is asked.
  ///
  /// [width] and [height] are a request, not a guarantee; the browser clamps
  /// them and remembers whatever the user last resized to.
  ///
  /// [copyStyles] carries the page's stylesheets into the new document, which
  /// starts with none at all. Flutter injects its own, so this mostly matters
  /// for web fonts declared on the page. Turn it off if you are drawing
  /// nothing but Flutter and want the window to open a few milliseconds sooner.
  ///
  /// [disallowReturnToOpener] hides the browser's "back to tab" button.
  ///
  /// [preferInitialWindowPlacement] asks for [width] and [height] rather than
  /// the geometry the user last left a window at. The browser may remember
  /// that per origin and reuse it, which is what you want when the same
  /// mini-player reopens — and not what you want when the next window shows
  /// something a different shape. Like [width] and [height] it is a hint, not
  /// a guarantee. Chrome 130 and later.
  ///
  /// Throws [DocumentPipUnsupported] where the API does not exist,
  /// [DocumentPipNotBootstrapped] when the app runner was never handed over,
  /// and [DocumentPipDenied] when the browser refuses.
  static Future<PipWindow> open({
    double width = 400,
    double height = 300,
    bool copyStyles = true,
    bool disallowReturnToOpener = false,
    bool preferInitialWindowPlacement = false,
  }) =>
      DocumentPipImpl.open(
        width: width,
        height: height,
        copyStyles: copyStyles,
        disallowReturnToOpener: disallowReturnToOpener,
        preferInitialWindowPlacement: preferInitialWindowPlacement,
      );
}
