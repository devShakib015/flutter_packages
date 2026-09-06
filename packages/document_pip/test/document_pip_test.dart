@TestOn('vm')
library;

// Runs on the VM, where there is no browser. These pin the off-web contract:
// the package must compile and refuse clearly, never pretend.
//
// @TestOn('vm') is load-bearing, not decoration: under `--platform chrome`
// isSupported is true and every assertion here inverts. The browser half of
// the suite lives in web_test.dart.
import 'package:document_pip/document_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('off the web', () {
    test('says so rather than guessing', () {
      expect(DocumentPip.isSupported, isFalse);
      expect(DocumentPip.current, isNull);
    });

    test('opening throws the unsupported case, not a missing member', () async {
      // The whole reason for the conditional export: a web-only package should
      // still compile on every platform and fail with something readable.
      await expectLater(
        DocumentPip.open(),
        throwsA(isA<DocumentPipUnsupported>()),
      );
    });
  });

  group('the failure a user will actually hit', () {
    test('the bootstrap error carries the snippet, not just a complaint', () {
      // This is the most likely failure by far, and the fix is not guessable
      // from the symptom, so the message has to teach.
      const DocumentPipNotBootstrapped e = DocumentPipNotBootstrapped();
      expect(e.message, contains('multiViewEnabled'));
      expect(e.message, contains('window.documentPipApp'));
      expect(e.message, contains('runWidget'));
      expect(e.message, contains('addView'));
    });

    test('the denied error names the user-gesture rule', () {
      const DocumentPipDenied e = DocumentPipDenied('NotAllowedError');
      expect(e.message, contains('NotAllowedError'));
    });

    test('every failure is one sealed family', () {
      // A switch over these is exhaustive, so adding a case later is a compile
      // error rather than a silent fall-through.
      String describe(DocumentPipException e) => switch (e) {
            DocumentPipUnsupported() => 'unsupported',
            DocumentPipDenied() => 'denied',
            DocumentPipNotBootstrapped() => 'not bootstrapped',
          };
      expect(describe(const DocumentPipUnsupported()), 'unsupported');
      expect(describe(const DocumentPipDenied('x')), 'denied');
      expect(describe(const DocumentPipNotBootstrapped()), 'not bootstrapped');
    });
  });

  group('DocumentPipApp', () {
    testWidgets('renders main into the one view a test has', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        DocumentPipApp(
          main: (BuildContext c) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('page'),
          ),
          popOut: (BuildContext c) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('floating'),
          ),
        ),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();

      // A widget test has exactly one view, and it is the page — so popOut
      // must not be built. Getting this backwards would show the mini player
      // in the main window.
      expect(find.text('page'), findsOneWidget);
      expect(find.text('floating'), findsNothing);
    });

    testWidgets('survives a metrics change without losing the tree', (
      WidgetTester tester,
    ) async {
      // Views appearing and disappearing arrive as metrics changes; that is
      // the only signal there is, so the rebuild path has to be safe to run
      // when nothing about the view set actually changed.
      await tester.pumpWidget(
        DocumentPipApp(
          main: (BuildContext c) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('page'),
          ),
          popOut: (BuildContext c) => const SizedBox.shrink(),
        ),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();

      tester.view.physicalSize = const Size(900, 700);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('page'), findsOneWidget);
    });
  });

  group('defects found in the pre-release audit', () {
    test('a view is only a pop-out if this package opened it', () {
      // Shipped in no release, caught before one. DocumentPipApp used to take
      // the LOWEST view id to be the page, which is wrong for any app with
      // more than one page-level view: add-to-app, or several Flutter hosts
      // on one page. Every host but the lowest would have rendered the mini
      // player into the main area.
      expect(DocumentPip.popOutViewIds, isEmpty);
    });

    testWidgets('with no pop-out open, every view gets main', (
      WidgetTester tester,
    ) async {
      // The consequence of the fix: a view this package did not open is the
      // page, whatever its id happens to be.
      await tester.pumpWidget(
        DocumentPipApp(
          main: (BuildContext c) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('page'),
          ),
          popOut: (BuildContext c) => const Directionality(
            textDirection: TextDirection.ltr,
            child: Text('floating'),
          ),
        ),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('page'), findsOneWidget);
      expect(find.text('floating'), findsNothing);
    });
  });

  group('the pop-out must not freeze when the tab goes to the background', () {
    // Measured in Chrome 152 while a pop-out was open and its tab backgrounded:
    // the opener's requestAnimationFrame advanced 302 times in 2.5s, against 2
    // for the identical page with no pop-out. Chromium keeps painting the
    // opener at full rate — and still reports visibilityState "hidden".
    //
    // Flutter believes the report, and that is the whole problem.
    testWidgets('Flutter stops drawing when the page reports itself hidden', (
      WidgetTester tester,
    ) async {
      Future<void> lifecycle(AppLifecycleState state) =>
          tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/lifecycle',
            const StringCodec().encodeMessage(state.toString()),
            (ByteData? _) {},
          );

      expect(tester.binding.framesEnabled, isTrue);

      await lifecycle(AppLifecycleState.hidden);
      // This is a regression guard on the FRAMEWORK, not on this package. If
      // it ever fails, Flutter changed its policy and the forced-frame pump in
      // DocumentPipApp can be deleted.
      expect(
        tester.binding.framesEnabled,
        isFalse,
        reason: 'a hidden page disables frames; that is why the pump exists',
      );

      await lifecycle(AppLifecycleState.resumed);
      expect(tester.binding.framesEnabled, isTrue);
    });

    testWidgets('scheduleForcedFrame is the way past it', (
      WidgetTester tester,
    ) async {
      // The other half of the fix: the escape hatch checks only whether a
      // frame is already pending, never framesEnabled. Pinned here because the
      // pump is worthless if this ever changes.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(AppLifecycleState.hidden.toString()),
        (ByteData? _) {},
      );
      expect(tester.binding.framesEnabled, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.scheduleFrame();
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'scheduleFrame is a no-op once frames are disabled',
      );

      tester.binding.scheduleForcedFrame();
      expect(tester.binding.hasScheduledFrame, isTrue);

      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(AppLifecycleState.resumed.toString()),
        (ByteData? _) {},
      );
    });
  });

  group('a resize must not rebuild both windows', () {
    testWidgets(
        'a metrics change that leaves the view set alone rebuilds nothing', (
      WidgetTester tester,
    ) async {
      // didChangeMetrics used to setState unconditionally. It fires on every
      // frame of a window drag — and this package feeds that loop itself by
      // resizing the pop-out's host — so dragging either window's edge re-ran
      // BOTH builders at frame rate. The example hid it by returning const
      // widgets; a real `MaterialApp(home: Player(...))` pays the whole tree.
      int mainBuilds = 0;
      int popOutBuilds = 0;
      await tester.pumpWidget(
        DocumentPipApp(
          main: (BuildContext c) {
            mainBuilds++;
            return const Directionality(
              textDirection: TextDirection.ltr,
              child: Text('page'),
            );
          },
          popOut: (BuildContext c) {
            popOutBuilds++;
            return const SizedBox.shrink();
          },
        ),
        wrapWithView: false,
      );
      await tester.pumpAndSettle();
      expect(mainBuilds, 1);
      expect(popOutBuilds, 0);

      addTearDown(tester.view.resetPhysicalSize);
      for (final Size size in const <Size>[
        Size(900, 700),
        Size(500, 400),
        Size(1200, 300),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
      }

      // Before the guard this was 4. Each View gives its own subtree a
      // MediaQuery, so the resize still reaches anything that asked for it.
      expect(mainBuilds, 1, reason: 'three resizes, no rebuilds');
      expect(popOutBuilds, 0);
      expect(find.text('page'), findsOneWidget);
    });

    // Not automatable, and worth saying so rather than writing a weaker test
    // that looks like proof: the inverse — a metrics change that DOES alter the
    // view set still rebuilds — needs a second real FlutterView.
    // TestPlatformDispatcher.addTestView drops the view it just added, so
    // there is no way to add one from a widget test. It is covered by
    // test/web_test.dart in a real browser instead.
  });

  group('options', () {
    test('preferInitialWindowPlacement is on open() and defaults to off',
        () async {
      // Off the web this only proves the parameter exists and threads through.
      // What it actually sends is asserted in the browser test.
      await expectLater(
        DocumentPip.open(preferInitialWindowPlacement: true),
        throwsA(isA<DocumentPipUnsupported>()),
      );
    });
  });
}
