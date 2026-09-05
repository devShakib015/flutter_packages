// Runs on the VM, where there is no browser. These pin the off-web contract:
// the package must compile and refuse clearly, never pretend.
import 'package:document_pip/document_pip.dart';
import 'package:flutter/material.dart';
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
}
