// Runs against a real iOS device or Simulator.
//
//   flutter test integration_test -d <device>
//
// The AR camera experience itself needs a real device, but the parts that
// decide whether a preview is even possible run anywhere, and they are the
// parts most likely to be wrong.
import 'dart:io';

import 'package:ar_quick_look/ar_quick_look.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the plugin registers and reports support', () async {
    // ignore: avoid_print
    print('  isSupported: ${ArQuickLook.isSupported}');
    expect(ArQuickLook.isSupported, isTrue, reason: 'this is an iOS run');
  });

  test('a file that is not there cannot be previewed', () async {
    expect(
      await ArQuickLook.canPreview('/tmp/nope-does-not-exist.usdz'),
      isFalse,
    );
  });

  test('the extension alone is not enough', () async {
    // The point of asking Quick Look rather than checking the suffix: a text
    // file renamed .usdz must come back false, or callers will present a
    // viewer that then fails.
    final File fake = File('${Directory.systemTemp.path}/not-really.usdz')
      ..writeAsStringSync('this is plainly not a USDZ archive');
    addTearDown(() => fake.existsSync() ? fake.deleteSync() : null);

    final bool answer = await ArQuickLook.canPreview(fake.path);
    // ignore: avoid_print
    print('  a text file named .usdz -> canPreview=$answer');
    expect(answer, isFalse);
  });

  test('presenting a missing file raises the typed exception', () async {
    await expectLater(
      ArQuickLook.present('/tmp/definitely-absent.usdz'),
      throwsA(isA<FileNotFoundException>()),
    );
  });

  test('presenting an unreadable file raises the typed exception', () async {
    final File fake = File('${Directory.systemTemp.path}/bad.usdz')
      ..writeAsStringSync('nope');
    addTearDown(() => fake.existsSync() ? fake.deleteSync() : null);
    await expectLater(
      ArQuickLook.present(fake.path),
      throwsA(isA<UnsupportedFileException>()),
    );
  });
}
