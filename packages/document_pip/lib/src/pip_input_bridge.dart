import 'dart:js_interop';
import 'dart:ui' show PlatformDispatcher, ViewFocusDirection, ViewFocusState;

import 'package:web/web.dart' as web;

/// Replays keyboard and selection events from a picture-in-picture window into
/// the opener, and tells Flutter which view has the keyboard.
///
/// Flutter's web engine binds the keyboard **once, globally**: `KeyboardBinding`
/// is a singleton that attaches capture-phase `keydown`/`keyup` listeners to
/// the opener's `window` (`keyboard_binding.dart`). A picture-in-picture window
/// is a separate browsing context with its own `window`, so while it has focus
/// the engine hears nothing at all. Typing still works — the browser routes
/// characters to the focused DOM input natively, and the engine reads them off
/// that element — but everything that travels as a *key event* is dead:
/// `Shortcuts`, `Actions`, `Focus.onKeyEvent`, `HardwareKeyboard`, Escape, and
/// Tab traversal.
///
/// Text selection has the same shape. All three of the engine's
/// `selectionchange` subscriptions are on the opener's `document`
/// (`text_editing.dart`), so moving the caret with the arrow keys inside a
/// pop-out never reaches Flutter's editing state.
///
/// Internal. Constructed by the web implementation when a window opens and
/// disposed with it; nothing about it is public API.
class PipInputBridge {
  /// Starts replaying [source]'s input into [target].
  ///
  /// [viewId] is the Flutter view rendering into [source], and is what focus
  /// is handed to when the window is focused.
  PipInputBridge.attach({
    required web.Window source,
    required web.Document target,
    required int viewId,
  })  : _source = source,
        _target = target,
        _viewId = viewId {
    // Capture, matching the engine: a page handler that stops propagation
    // should not be able to swallow the replay before it starts.
    _source.addEventListener('keydown', _onKeyRef, true.toJS);
    _source.addEventListener('keyup', _onKeyRef, true.toJS);
    _source.addEventListener('focus', _onFocusRef);
    _source.addEventListener('blur', _onBlurRef);
    _source.document.addEventListener('selectionchange', _onSelectionRef);
  }

  final web.Window _source;
  final web.Document _target;
  final int _viewId;

  /// Keys forwarded down and not yet up, as code -> key.
  ///
  /// Held so they can be released if the window loses focus or closes
  /// mid-press. Without it `HardwareKeyboard` believes they are still held and
  /// the next real press of the same key trips its consistency assertion.
  final Map<String, String> _pressed = <String, String>{};

  bool _disposed = false;

  // One tear-off each, kept: every `.toJS` makes a NEW JS function, so
  // removing with a second one silently leaves the listener attached.
  late final JSFunction _onKeyRef = _onKey.toJS;
  late final JSFunction _onFocusRef = _onFocus.toJS;
  late final JSFunction _onBlurRef = _onBlur.toJS;
  late final JSFunction _onSelectionRef = _onSelectionChange.toJS;

  void _onKey(web.Event event) {
    if (_disposed) return;
    final web.KeyboardEvent e = event as web.KeyboardEvent;
    final web.HTMLElement? body = _target.body;
    if (body == null) return;

    if (e.type == 'keydown') {
      _pressed[e.code] = e.key;
    } else {
      _pressed.remove(e.code);
    }

    // dispatchEvent returns false when something called preventDefault. The
    // engine does exactly that, synchronously, when the framework consumed the
    // key — so the return value is a truthful "Flutter handled this", and
    // mirroring it stops the browser acting on the key as well.
    final bool notPrevented = body.dispatchEvent(_replay(e.type, e.key, e.code,
        location: e.location,
        repeat: e.repeat,
        isComposing: e.isComposing,
        keyCode: e.keyCode,
        charCode: e.charCode,
        ctrl: e.ctrlKey,
        shift: e.shiftKey,
        alt: e.altKey,
        meta: e.metaKey,
        altGraph: e.getModifierState('AltGraph'),
        capsLock: e.getModifierState('CapsLock'),
        numLock: e.getModifierState('NumLock'),
        scrollLock: e.getModifierState('ScrollLock')));
    if (!notPrevented) e.preventDefault();
  }

  static web.KeyboardEvent _replay(
    String type,
    String key,
    String code, {
    int location = 0,
    bool repeat = false,
    bool isComposing = false,
    int keyCode = 0,
    int charCode = 0,
    bool ctrl = false,
    bool shift = false,
    bool alt = false,
    bool meta = false,
    bool altGraph = false,
    bool capsLock = false,
    bool numLock = false,
    bool scrollLock = false,
  }) =>
      web.KeyboardEvent(
        type,
        web.KeyboardEventInit(
          key: key,
          code: code,
          location: location,
          repeat: repeat,
          isComposing: isComposing,
          keyCode: keyCode,
          charCode: charCode,
          ctrlKey: ctrl,
          shiftKey: shift,
          altKey: alt,
          metaKey: meta,
          modifierAltGraph: altGraph,
          modifierCapsLock: capsLock,
          modifierNumLock: numLock,
          modifierScrollLock: scrollLock,
          // Dispatched at <body> so the engine's window-level capture listener
          // is on the propagation path, and so is anything the app put on the
          // document. Cancelable, or preventDefault above means nothing.
          bubbles: true,
          cancelable: true,
          composed: true,
        ),
      );

  /// Hands Flutter focus to the pop-out's view when the window takes it.
  ///
  /// Without this, forwarded keys arrive but land on whatever the page had
  /// focused last — trading "the keys do nothing" for the worse "the keys
  /// drive the wrong window". Nothing in the pop-out has DOM focus right after
  /// it opens, so the engine's own focusin listeners never fire.
  void _onFocus(web.Event _) {
    if (_disposed) return;
    PlatformDispatcher.instance.requestViewFocusChange(
      viewId: _viewId,
      state: ViewFocusState.focused,
      direction: ViewFocusDirection.forward,
    );
  }

  void _onBlur(web.Event _) {
    if (_disposed) return;
    _releasePressed();
  }

  /// Forwards a bare `selectionchange` when the caret moved inside the
  /// pop-out's text editing host.
  ///
  /// Safe to over-send: the engine ignores the event object and re-reads the
  /// editing state off the active element, bailing out when it has not
  /// changed. The guard is there so an ordinary selection elsewhere in the
  /// pop-out does not wake the text editor for nothing.
  void _onSelectionChange(web.Event _) {
    if (_disposed) return;
    final web.Element? active = _source.document.activeElement;
    if (active == null) return;
    if (active.closest('flt-text-editing-host') == null) return;
    _target.dispatchEvent(web.Event('selectionchange'));
  }

  void _releasePressed() {
    if (_pressed.isEmpty) return;
    final web.HTMLElement? body = _target.body;
    if (body != null) {
      _pressed.forEach((String code, String key) {
        body.dispatchEvent(_replay('keyup', key, code));
      });
    }
    _pressed.clear();
  }

  /// Detaches everything and releases any key still held.
  void dispose() {
    if (_disposed) return;
    _releasePressed();
    _disposed = true;
    try {
      _source.removeEventListener('keydown', _onKeyRef, true.toJS);
      _source.removeEventListener('keyup', _onKeyRef, true.toJS);
      _source.removeEventListener('focus', _onFocusRef);
      _source.removeEventListener('blur', _onBlurRef);
      _source.document.removeEventListener('selectionchange', _onSelectionRef);
    } catch (_) {
      // The window may already be gone; nothing to detach from.
    }
  }
}
