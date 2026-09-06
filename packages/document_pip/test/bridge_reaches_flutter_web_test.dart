@TestOn('browser')
library;

// The claim the keyboard bridge rests on, tested end to end rather than at the
// DOM boundary: a key pressed in the pop-out must reach FLUTTER — Shortcuts,
// Actions, the focus tree — not merely arrive at a listener on window.
//
// The other bridge tests assert the DOM contract. This one asserts the thing a
// user cares about, and it is the one that would catch the engine starting to
// ignore replayed events (they are isTrusted: false, and nothing documents that
// the engine will keep accepting them).
import 'dart:async';
import 'dart:js_interop';

import 'package:document_pip/src/pip_input_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

class _ProbeIntent extends Intent {
  const _ProbeIntent();
}

void main() {
  late web.HTMLIFrameElement frame;
  late web.Window source;
  PipInputBridge? bridge;

  setUp(() async {
    frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
    frame.src = 'about:blank';
    web.document.body!.appendChild(frame);
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
  });

  tearDown(() {
    bridge?.dispose();
    bridge = null;
    frame.remove();
  });

  /// Returns the keydown, so a caller can see whether Flutter consumed it.
  web.KeyboardEvent typeInPopOut(String key, String code) {
    final web.KeyboardEvent down = web.KeyboardEvent(
      'keydown',
      web.KeyboardEventInit(
        key: key,
        code: code,
        bubbles: true,
        cancelable: true,
        composed: true,
      ),
    );
    source.document.body!.dispatchEvent(down);
    source.document.body!.dispatchEvent(
      web.KeyboardEvent(
        'keyup',
        web.KeyboardEventInit(
          key: key,
          code: code,
          bubbles: true,
          cancelable: true,
          composed: true,
        ),
      ),
    );
    return down;
  }

  /// Mounts a Shortcuts/Actions tree, attaches the bridge, and returns the
  /// keydown that was replayed plus what fired.
  Future<(web.KeyboardEvent, List<String>)> pressThrough(
    WidgetTester tester,
    String key,
    String code,
  ) async {
    final List<String> fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            LogicalKeySet(LogicalKeyboardKey.keyJ): const _ProbeIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ProbeIntent: CallbackAction<_ProbeIntent>(
                onInvoke: (_ProbeIntent intent) {
                  fired.add('j');
                  return null;
                },
              ),
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    bridge = PipInputBridge.attach(
      source: source,
      target: web.document,
      viewId: WidgetsBinding.instance.platformDispatcher.views.first.viewId,
    );
    final web.KeyboardEvent down = typeInPopOut(key, code);
    await tester.pump(const Duration(milliseconds: 50));
    return (down, fired);
  }

  testWidgets('WITHOUT the bridge, Flutter never sees the key', (
    WidgetTester tester,
  ) async {
    final List<String> fired = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            LogicalKeySet(LogicalKeyboardKey.keyJ): const _ProbeIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              _ProbeIntent: CallbackAction<_ProbeIntent>(
                onInvoke: (_ProbeIntent intent) {
                  fired.add('j');
                  return null;
                },
              ),
            },
            child: const Focus(autofocus: true, child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    typeInPopOut('j', 'KeyJ');
    await tester.pump(const Duration(milliseconds: 50));
    expect(fired, isEmpty);
  });

  testWidgets('a key typed in the pop-out fires a Shortcuts action', (
    WidgetTester tester,
  ) async {
    final (_, List<String> fired) = await pressThrough(tester, 'j', 'KeyJ');
    expect(fired, <String>['j']);
  });

  testWidgets('Flutter handling a key does NOT mark the original prevented', (
    WidgetTester tester,
  ) async {
    // Pinning what actually happens, not what would be nice. The bridge mirrors
    // dispatchEvent's return onto the real event, so a key Flutter consumed
    // would not also trigger the browser's default. Measured here, the engine
    // does NOT report consumption for a key a Shortcuts handler acted on — the
    // action fires and defaultPrevented stays false — so that mirroring is
    // inert today.
    //
    // The mirroring stays anyway: it is a pass-through that costs nothing while
    // the engine is silent and becomes correct the moment it is not. If this
    // test starts failing, that is what happened, and the README's "browser
    // defaults still fire inside the pop-out" caveat can go with it.
    final (web.KeyboardEvent down, List<String> fired) = await pressThrough(
      tester,
      'j',
      'KeyJ',
    );
    expect(fired, <String>['j'], reason: 'Flutter did handle the key');
    expect(down.defaultPrevented, isFalse);
  });

  testWidgets('a key Flutter IGNORED keeps its browser default', (
    WidgetTester tester,
  ) async {
    final (web.KeyboardEvent down, List<String> fired) = await pressThrough(
      tester,
      'q',
      'KeyQ',
    );
    expect(fired, isEmpty, reason: 'precondition: Flutter ignored it');
    expect(down.defaultPrevented, isFalse);
  });
}
