@TestOn('browser')
library;

// Real Chrome, via `flutter test --platform chrome`.
//
// The subject is the keyboard bridge. A same-origin iframe stands in for the
// picture-in-picture window: it is a genuinely separate browsing context with
// its own `window` and `document`, which is the only property that matters
// here — and unlike a real pop-out it needs no user gesture, so this runs
// headlessly and in CI.
import 'dart:async';
import 'dart:js_interop';

import 'package:document_pip/src/pip_input_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late web.HTMLIFrameElement frame;
  late web.Window source;
  late List<web.KeyboardEvent> received;
  late JSFunction spy;
  PipInputBridge? bridge;

  setUp(() async {
    frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    frame.src = 'about:blank';
    web.document.body!.appendChild(frame);
    // about:blank resolves on a microtask in Chrome, but wait for the load
    // rather than assuming it.
    if (frame.contentDocument?.body == null) {
      final Completer<void> loaded = Completer<void>();
      frame.addEventListener(
        'load',
        ((web.Event _) {
          if (!loaded.isCompleted) loaded.complete();
        }).toJS,
      );
      await loaded.future.timeout(const Duration(seconds: 5));
    }
    source = frame.contentWindow!;

    received = <web.KeyboardEvent>[];
    spy = ((web.Event e) => received.add(e as web.KeyboardEvent)).toJS;
    // Capture on the top-level window: exactly where Flutter's KeyboardBinding
    // attaches (keyboard_binding.dart -> domWindow.addEventListener(..., true)).
    web.window.addEventListener('keydown', spy, true.toJS);
    web.window.addEventListener('keyup', spy, true.toJS);
  });

  tearDown(() {
    bridge?.dispose();
    bridge = null;
    web.window.removeEventListener('keydown', spy, true.toJS);
    web.window.removeEventListener('keyup', spy, true.toJS);
    frame.remove();
  });

  void attach() => bridge = PipInputBridge.attach(
        source: source,
        target: web.document,
        viewId: 0,
      );

  web.KeyboardEvent press(
    String type,
    String key,
    String code, {
    bool ctrl = false,
    bool shift = false,
    bool repeat = false,
    int location = 0,
    int keyCode = 0,
  }) {
    final web.KeyboardEvent e = web.KeyboardEvent(
      type,
      web.KeyboardEventInit(
        key: key,
        code: code,
        ctrlKey: ctrl,
        shiftKey: shift,
        repeat: repeat,
        location: location,
        keyCode: keyCode,
        bubbles: true,
        cancelable: true,
        composed: true,
      ),
    );
    source.document.body!.dispatchEvent(e);
    return e;
  }

  test('WITHOUT the bridge, a key in the pop-out never reaches the engine', () {
    // The defect itself, stated as a test. Flutter binds the keyboard once, to
    // the opener's window, so a separate browsing context is simply not on the
    // propagation path. If this ever starts failing the bridge is obsolete.
    press('keydown', 'a', 'KeyA');
    expect(received, isEmpty);
  });

  test('with the bridge, it arrives exactly once and intact', () {
    attach();
    press('keydown', 'S', 'KeyS', ctrl: true, shift: true, keyCode: 83);

    expect(received, hasLength(1));
    final web.KeyboardEvent got = received.single;
    expect(got.type, 'keydown');
    expect(got.key, 'S');
    expect(got.code, 'KeyS');
    expect(got.ctrlKey, isTrue);
    expect(got.shiftKey, isTrue);
    expect(got.altKey, isFalse);
    expect(got.metaKey, isFalse);
    expect(got.keyCode, 83);
  });

  test('location and repeat survive the replay', () {
    // The converter distinguishes left from right modifiers by location, and
    // an auto-repeating key from a fresh press by repeat. Dropping either
    // gives Flutter a subtly wrong key.
    attach();
    press('keydown', 'Shift', 'ShiftRight', shift: true, location: 2);
    press('keydown', 'a', 'KeyA', repeat: true);

    expect(received, hasLength(2));
    expect(received[0].location, 2);
    expect(received[0].code, 'ShiftRight');
    expect(received[1].repeat, isTrue);
  });

  test('keyup forwards too', () {
    // Forwarding only keydown would leave HardwareKeyboard believing every key
    // is held forever, and its consistency assertion fires on the next press.
    attach();
    press('keydown', 'a', 'KeyA');
    press('keyup', 'a', 'KeyA');
    expect(received.map((web.KeyboardEvent e) => e.type), <String>[
      'keydown',
      'keyup',
    ]);
  });

  test('"Flutter consumed it" travels back to the real event', () {
    // The whole contract in one assertion. The engine calls preventDefault
    // synchronously when the framework handled the key; the bridge mirrors
    // that onto the original so the browser does not also act on it.
    attach();
    final JSFunction consume = ((web.Event e) => e.preventDefault()).toJS;
    web.document.body!.addEventListener('keydown', consume);
    addTearDown(
      () => web.document.body!.removeEventListener('keydown', consume),
    );

    final web.KeyboardEvent original = press('keydown', 'Tab', 'Tab');
    expect(original.defaultPrevented, isTrue);
  });

  test('an unconsumed key leaves the original alone', () {
    // The inverse, so the test above is not passing because everything is
    // marked prevented.
    attach();
    final web.KeyboardEvent original = press('keydown', 'Tab', 'Tab');
    expect(original.defaultPrevented, isFalse);
  });

  test('a key held when the window goes away is released', () {
    attach();
    press('keydown', 'Control', 'ControlLeft', ctrl: true);
    received.clear();

    bridge!.dispose();
    bridge = null;

    // A synthetic keyup for the held key, or the next real Control press
    // arrives while HardwareKeyboard still thinks it is down.
    expect(received, hasLength(1));
    expect(received.single.type, 'keyup');
    expect(received.single.code, 'ControlLeft');
    expect(received.single.key, 'Control');
  });

  test('after dispose nothing is forwarded at all', () {
    attach();
    bridge!.dispose();
    bridge = null;
    received.clear();

    press('keydown', 'a', 'KeyA');
    press('keyup', 'a', 'KeyA');
    expect(received, isEmpty);
  });

  group('selection', () {
    late int forwarded;
    late JSFunction selectionSpy;

    setUp(() {
      forwarded = 0;
      selectionSpy = ((web.Event _) => forwarded++).toJS;
      web.document.addEventListener('selectionchange', selectionSpy);
    });

    tearDown(() {
      web.document.removeEventListener('selectionchange', selectionSpy);
    });

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 50));

    test('a caret move inside the text editing host is forwarded', () async {
      // All three of the engine's selectionchange subscriptions are on the
      // OPENER's document, so without this arrow keys in a pop-out TextField
      // move the browser caret and Flutter never learns.
      attach();
      final web.Element host =
          source.document.createElement('flt-text-editing-host');
      final web.HTMLInputElement input =
          source.document.createElement('input') as web.HTMLInputElement;
      host.appendChild(input);
      source.document.body!.appendChild(host);

      input.value = 'hello';
      input.focus();
      input.setSelectionRange(2, 2);
      // setSelectionRange queues selectionchange as a task; reading the
      // counter synchronously would read zero and pass for the wrong reason.
      await settle();

      expect(forwarded, greaterThanOrEqualTo(1));
    });

    test('a selection outside the host is not', () async {
      // The guard. Selecting ordinary text in the pop-out must not wake the
      // text editor on the opener.
      attach();
      final web.HTMLInputElement loose =
          source.document.createElement('input') as web.HTMLInputElement;
      source.document.body!.appendChild(loose);

      loose.value = 'hello';
      loose.focus();
      loose.setSelectionRange(1, 3);
      await settle();

      expect(forwarded, 0);
    });
  });
}
