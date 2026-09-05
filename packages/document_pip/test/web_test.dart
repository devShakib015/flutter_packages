@TestOn('browser')
library;

// These run in a real Chrome via `flutter test --platform chrome`. They cover
// the two things the VM cannot: that the API is detected, and that the two
// failures a user hits are the ones they actually get.
import 'package:document_pip/document_pip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the API is detected in a Chromium browser', () {
    // If this ever fails in CI it means the API was withdrawn or the browser
    // changed, which is worth knowing loudly rather than through a bug report.
    expect(DocumentPip.isSupported, isTrue);
  });

  test('nothing is open to begin with', () {
    expect(DocumentPip.current, isNull);
  });

  test('a test harness has no app runner, so it says exactly that', () async {
    // The test page is not booted through the multi-view bootstrap, so
    // window.documentPipApp is absent — the same state a user is in when they
    // skip that step, which is the single most likely way to meet this
    // package failing.
    await expectLater(
      DocumentPip.open(),
      throwsA(
        isA<DocumentPipNotBootstrapped>().having(
          (DocumentPipNotBootstrapped e) => e.message,
          'message',
          allOf(
            contains('multiViewEnabled'),
            contains('window.documentPipApp'),
          ),
        ),
      ),
    );
  });

  test('the bootstrap check runs before the window is asked for', () async {
    // Deliberate ordering: checking after would leave a window on screen that
    // nothing can render into, and would also spend the user gesture.
    // Reaching NotBootstrapped rather than Denied proves the order, because
    // there is no user gesture in a test either.
    Object? thrown;
    try {
      await DocumentPip.open();
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isA<DocumentPipNotBootstrapped>());
    expect(thrown, isNot(isA<DocumentPipDenied>()));
  });
}
