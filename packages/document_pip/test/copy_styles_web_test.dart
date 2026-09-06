@TestOn('browser')
library;

// Real Chrome. The subject is what `copyStyles: true` actually carries into
// the new document, asserted with computed styles rather than by eye.
//
// A same-origin iframe stands in for the picture-in-picture window: same
// property that matters — a separate document that starts with no styles.
import 'dart:async';
import 'dart:js_interop';

import 'package:document_pip/src/web_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  late web.HTMLIFrameElement frame;
  late web.Document target;
  final List<web.Element> injected = <web.Element>[];

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
    target = frame.contentDocument!;
  });

  tearDown(() {
    for (final web.Element e in injected) {
      e.remove();
    }
    injected.clear();
    web.document.documentElement!.removeAttribute('class');
    web.document.documentElement!.removeAttribute('lang');
    web.document.documentElement!.removeAttribute('dir');
    web.document.documentElement!.removeAttribute('data-theme');
    frame.remove();
  });

  void injectStyle(String css) {
    final web.HTMLStyleElement s =
        web.document.createElement('style') as web.HTMLStyleElement;
    s.textContent = css;
    web.document.head!.appendChild(s);
    injected.add(s);
  }

  test('stylesheets reach the new document', () {
    injectStyle('.probe { color: rgb(4, 5, 6) }');
    final web.HTMLDivElement probe =
        target.createElement('div') as web.HTMLDivElement;
    probe.className = 'probe';
    target.body!.appendChild(probe);

    // Before: a blank document has none of the page's CSS at all.
    expect(
      frame.contentWindow!.getComputedStyle(probe).color,
      isNot('rgb(4, 5, 6)'),
    );

    DocumentPipImpl.copyStyleSheets(target);
    expect(frame.contentWindow!.getComputedStyle(probe).color, 'rgb(4, 5, 6)');
  });

  test('the attributes that CSS selects on reach it too', () {
    // The defect: copying the stylesheets is only half of it. Every themed app
    // puts its state on <html> — `class="dark"`, `data-theme`, `dir="rtl"` —
    // and a rule keyed on that matched nothing in the pop-out.
    web.document.documentElement!.className = 'dark';
    web.document.documentElement!.setAttribute('data-theme', 'high-contrast');
    injectStyle(
      'html.dark { --probe: rgb(7, 8, 9) } '
      'html[data-theme="high-contrast"] .probe { font-weight: 800 } '
      '.probe { color: var(--probe, rgb(0, 0, 0)) }',
    );

    final web.HTMLDivElement probe =
        target.createElement('div') as web.HTMLDivElement;
    probe.className = 'probe';
    target.body!.appendChild(probe);

    DocumentPipImpl.copyStyleSheets(target);
    // Stylesheets alone: the rules are there but nothing matches them.
    expect(
      frame.contentWindow!.getComputedStyle(probe).color,
      'rgb(0, 0, 0)',
      reason: 'without the class, html.dark cannot match',
    );

    DocumentPipImpl.copyRootAttributes(
      web.document.documentElement,
      target.documentElement,
    );
    expect(frame.contentWindow!.getComputedStyle(probe).color, 'rgb(7, 8, 9)');
    expect(frame.contentWindow!.getComputedStyle(probe).fontWeight, '800');
  });

  test('dir and lang carry over', () {
    web.document.documentElement!.setAttribute('dir', 'rtl');
    web.document.documentElement!.setAttribute('lang', 'ar');

    DocumentPipImpl.copyRootAttributes(
      web.document.documentElement,
      target.documentElement,
    );

    expect(target.documentElement!.getAttribute('dir'), 'rtl');
    expect(target.documentElement!.getAttribute('lang'), 'ar');
  });

  test('the layout reset is merged, not slammed over what was copied', () {
    // The reset used to be setAttribute('style', ...), which would have thrown
    // away any inline style copied in a moment earlier.
    target.documentElement!.setAttribute('style', 'background: rgb(1, 2, 3)');
    DocumentPipImpl.mergeStyle(target.documentElement, 'height:100%');

    final String style = target.documentElement!.getAttribute('style')!;
    expect(style, contains('rgb(1, 2, 3)'));
    expect(style, contains('height'));
  });

  test('merging onto nothing does not produce a stray semicolon', () {
    DocumentPipImpl.mergeStyle(target.body, 'margin:0');
    expect(target.body!.getAttribute('style'), 'margin:0');
  });
}
