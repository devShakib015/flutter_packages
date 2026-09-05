import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'exceptions.dart';
import 'interop.dart';
import 'pip_window.dart';

/// The real implementation: opens the window, gives Flutter a host inside it,
/// and tears both down together.
class DocumentPipImpl {
  static _WebPipWindow? _current;
  static final Set<int> _pipViewIds = <int>{};

  /// The views this package opened.
  ///
  /// Exact, rather than inferred from view ids: an app may add page-level
  /// views of its own, and guessing would render the pop-out into one of them.
  static Set<int> get popOutViewIds => Set<int>.unmodifiable(_pipViewIds);

  /// Whether this browser has the API at all.
  static bool get isSupported => documentPictureInPicture != null;

  /// The open window, or null.
  static PipWindow? get current => _current?.isOpen ?? false ? _current : null;

  /// Opens a window and renders a Flutter view into it.
  static Future<PipWindow> open({
    required double width,
    required double height,
    required bool copyStyles,
    required bool disallowReturnToOpener,
  }) async {
    final DocumentPictureInPicture? api = documentPictureInPicture;
    if (api == null) throw const DocumentPipUnsupported();

    // Checked before opening the window rather than after: failing here leaves
    // nothing on screen to clean up, and the message can teach.
    final FlutterAppRunner? app = documentPipApp;
    if (app == null) throw const DocumentPipNotBootstrapped();

    if (_current?.isOpen ?? false) await _current!.close();

    final web.Window pip;
    try {
      pip = await api
          .requestWindow(
            PipOptions(
              width: width.round(),
              height: height.round(),
              disallowReturnToOpener: disallowReturnToOpener,
            ),
          )
          .toDart;
    } catch (e) {
      // Overwhelmingly the missing user gesture. Say so rather than surfacing
      // a bare DOMException, because the fix is not obvious from the text.
      throw DocumentPipDenied(
        'The browser refused to open the window: $e\n\n'
        'This is nearly always the user-gesture rule — requestWindow may only '
        'run while handling a real click, tap or key press. Awaiting anything '
        'first spends the gesture, so call DocumentPip.open() before any other '
        'await in your handler.',
      );
    }

    if (copyStyles) _copyStyles(pip.document);

    // A blank window has no layout of its own, so the host is given one and
    // the body's default margin removed. Without this the Flutter view
    // measures zero and paints nothing.
    pip.document.documentElement?.setAttribute('style', 'height:100%');
    pip.document.body!.setAttribute(
      'style',
      'margin:0;padding:0;height:100%;overflow:hidden',
    );
    final web.HTMLDivElement host =
        pip.document.createElement('div') as web.HTMLDivElement;
    // Explicit pixels rather than `inset:0`, and set *before* the element is
    // in the tree: Flutter puts a ResizeObserver on its host, and a host whose
    // size is still resolving makes that observer fire inside its own
    // callback, which the browser reports as "ResizeObserver loop completed
    // with undelivered notifications" in the console of anyone using this.
    host.setAttribute(
      'style',
      'display:block;position:absolute;left:0;top:0;'
          'width:${pip.innerWidth}px;height:${pip.innerHeight}px',
    );
    pip.document.body!.appendChild(host);

    // The window is resizable, so the host has to follow it.
    pip.addEventListener(
      'resize',
      ((web.Event _) {
        host.style.width = '${pip.innerWidth}px';
        host.style.height = '${pip.innerHeight}px';
      }).toJS,
    );

    final int viewId = app.addView(AddViewOptions(hostElement: host));
    _pipViewIds.add(viewId);
    final _WebPipWindow handle = _WebPipWindow(viewId, pip, app);
    _current = handle;
    return handle;
  }

  /// Copies the opener's stylesheets into the new document.
  ///
  /// A picture-in-picture window starts with no styles whatsoever — not the
  /// page's, not the user agent's cascade from the opener. Flutter injects its
  /// own into the head, so most of this matters for surrounding HTML rather
  /// than the canvas, but fonts declared on the page are the exception and
  /// they matter a lot.
  static void _forget(_WebPipWindow w) {
    _pipViewIds.remove(w.viewId);
    // Otherwise the static keeps a dead window, and its document, alive.
    if (identical(_current, w)) _current = null;
  }

  static void _copyStyles(web.Document target) {
    final web.StyleSheetList sheets = web.document.styleSheets;
    for (int i = 0; i < sheets.length; i++) {
      final web.StyleSheet sheet = sheets.item(i)!;
      try {
        final web.CSSRuleList rules = (sheet as web.CSSStyleSheet).cssRules;
        final StringBuffer css = StringBuffer();
        for (int r = 0; r < rules.length; r++) {
          css.writeln(rules.item(r)!.cssText);
        }
        final web.HTMLStyleElement style =
            target.createElement('style') as web.HTMLStyleElement;
        style.textContent = css.toString();
        target.head!.appendChild(style);
      } catch (_) {
        // A cross-origin stylesheet throws on cssRules. Re-link it instead so
        // a Google Fonts <link> still applies in the new window.
        final web.Element? owner = sheet.ownerNode as web.Element?;
        if (owner != null) {
          // importNode, not cloneNode: a clone still belongs to the source
          // document, and adopting it explicitly is what the DOM spec asks for.
          target.head!.appendChild(target.importNode(owner, true));
        }
      }
    }
  }
}

class _WebPipWindow implements PipWindow {
  _WebPipWindow(this.viewId, this._window, this._app) {
    // The user can close the window themselves, and the browser closes it if
    // another one opens — only one exists per browser. Either way the Flutter
    // view has to go, or it renders into a document nobody can see.
    // _onGoneRef, not _onGone.toJS: every `.toJS` on a tear-off makes a NEW
    // JS function, so adding with one and removing with another silently
    // leaves the listener attached forever.
    _window.addEventListener('pagehide', _onGoneRef);
  }

  @override
  final int viewId;

  final web.Window _window;
  final FlutterAppRunner _app;
  final Completer<void> _closed = Completer<void>();
  bool _open = true;

  late final JSFunction _onGoneRef = _onGone.toJS;

  void _onGone(web.Event _) => _teardown();

  @override
  bool get isOpen => _open;

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> close() async {
    if (!_open) return;
    _teardown();
    _window.close();
  }

  void _teardown() {
    if (!_open) return;
    _open = false;
    try {
      _window.removeEventListener('pagehide', _onGoneRef);
    } catch (_) {
      // The window may already be gone; nothing to detach from.
    }
    _app.removeView(viewId);
    DocumentPipImpl._forget(this);
    if (!_closed.isCompleted) _closed.complete();
  }
}
