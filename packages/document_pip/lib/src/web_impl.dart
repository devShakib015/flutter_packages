import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'exceptions.dart';
import 'interop.dart';
import 'pip_input_bridge.dart';
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
    required bool preferInitialWindowPlacement,
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
              preferInitialWindowPlacement: preferInitialWindowPlacement,
            ),
          )
          .toDart;
    } catch (e) {
      // Do not assert a cause the browser did not give. Chrome refuses for
      // three different reasons and reports all of them as NotAllowedError, so
      // the name cannot discriminate — but its message can, and it is in $e.
      // An earlier version blamed the user gesture unconditionally, which sent
      // anyone running inside an iframe to go and fix a correct click handler.
      throw DocumentPipDenied(
        'The browser refused to open the window: $e\n\n'
        'Chrome refuses for three reasons and its own message above says '
        'which:\n'
        '  - No live user gesture. DocumentPip.open() must be the first await '
        'in a real click, tap or key-press handler; awaiting anything before '
        'it spends the gesture.\n'
        '  - The call came from an iframe rather than the top-level page.\n'
        '  - The call came from inside a picture-in-picture window.',
      );
    }

    if (copyStyles) {
      copyStyleSheets(pip.document);
      // The stylesheets alone are not enough: `html.dark .card {}` needs the
      // class too, and RTL needs `dir`. A blank window inherits no attributes.
      copyRootAttributes(
          web.document.documentElement, pip.document.documentElement);
      copyRootAttributes(web.document.body, pip.document.body);
    }

    // A blank window has no layout of its own, so the host is given one and
    // the body's default margin removed. Without this the Flutter view
    // measures zero and paints nothing. Merged, not assigned: the opener's
    // own inline style may have just been copied in above.
    mergeStyle(pip.document.documentElement, 'height:100%');
    mergeStyle(
      pip.document.body,
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

    // The window is resizable, so the host has to follow it. The tear-off is
    // kept so _teardown can actually detach it: every `.toJS` makes a NEW JS
    // function, so removing with a second one silently does nothing and the
    // listener outlives the window it was watching.
    void onResize(web.Event _) {
      host.style.width = '${pip.innerWidth}px';
      host.style.height = '${pip.innerHeight}px';
    }

    final JSFunction onResizeRef = onResize.toJS;
    pip.addEventListener('resize', onResizeRef);

    final int viewId = app.addView(AddViewOptions(hostElement: host));
    _pipViewIds.add(viewId);
    // Flutter binds the keyboard to the opener's window, once. Without this
    // bridge every key event in the pop-out is dropped: no Shortcuts, no
    // Escape, no Tab traversal. See PipInputBridge.
    final PipInputBridge input = PipInputBridge.attach(
      source: pip,
      target: web.document,
      viewId: viewId,
    );
    final _WebPipWindow handle =
        _WebPipWindow(viewId, pip, app, onResizeRef, input);
    _current = handle;
    return handle;
  }

  static void _forget(_WebPipWindow w) {
    _pipViewIds.remove(w.viewId);
    // Otherwise the static keeps a dead window, and its document, alive.
    if (identical(_current, w)) _current = null;
  }

  /// Appends [css] to whatever inline style [el] already carries.
  ///
  /// Not private only so the browser tests can drive it. This library is not
  /// exported from the barrel, so none of it is public API.
  static void mergeStyle(web.Element? el, String css) {
    if (el == null) return;
    final String existing = (el.getAttribute('style') ?? '').trimRight();
    final String sep = existing.isEmpty || existing.endsWith(';') ? '' : ';';
    el.setAttribute('style', '$existing$sep$css');
  }

  /// Carries the attributes the opener's CSS selects on into the new document.
  ///
  /// Copying the stylesheets is only half of it. A theme switcher that sets
  /// `class="dark"` on `<html>`, an app that keys off `data-density`, or any
  /// page with `dir="rtl"` gets rules that match nothing without this.
  static void copyRootAttributes(web.Element? from, web.Element? to) {
    if (from == null || to == null) return;
    for (final String name in const <String>['class', 'dir', 'lang']) {
      final String? value = from.getAttribute(name);
      if (value != null) to.setAttribute(name, value);
    }
    final web.NamedNodeMap attrs = from.attributes;
    for (int i = 0; i < attrs.length; i++) {
      final web.Attr attr = attrs.item(i)!;
      if (attr.name.startsWith('data-')) to.setAttribute(attr.name, attr.value);
    }
    // `style` is handled by mergeStyle so the layout reset can be appended
    // rather than clobbering what was copied.
    final String? style = from.getAttribute('style');
    if (style != null) to.setAttribute('style', style);
  }

  /// Copies the opener's stylesheets into the new document.
  ///
  /// A picture-in-picture window starts with no styles whatsoever — not the
  /// page's, not the user agent's cascade from the opener. Flutter injects its
  /// own into the head, so most of this matters for surrounding HTML rather
  /// than the canvas, but fonts declared on the page are the exception and
  /// they matter a lot.
  static void copyStyleSheets(web.Document target) {
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
  _WebPipWindow(
    this.viewId,
    this._window,
    this._app,
    this._onResizeRef,
    this._input,
  ) {
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
  final JSFunction _onResizeRef;
  final PipInputBridge _input;
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
    _input.dispose();
    try {
      _window.removeEventListener('pagehide', _onGoneRef);
      _window.removeEventListener('resize', _onResizeRef);
    } catch (_) {
      // The window may already be gone; nothing to detach from.
    }
    // Forget first. removeView disposes the view, and the engine's
    // _onViewDisposedController is a *synchronous* broadcast stream that ends
    // in invokeOnMetricsChanged — so anything listening for a metrics change
    // runs inside this call, and would otherwise still see the dead id here.
    DocumentPipImpl._forget(this);
    _app.removeView(viewId);
    if (!_closed.isCompleted) _closed.complete();
  }
}
