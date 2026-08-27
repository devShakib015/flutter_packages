// Verifies the hosted native text view on a real device or Simulator.
//
// macOS was checked during development; this is the same check on iOS, where
// the platform-view plumbing is completely different code.
import 'package:apple_intelligence/apple_intelligence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the hosted text view attaches, reports, and round-trips', (
    WidgetTester tester,
  ) async {
    final NativeTextController c = NativeTextController();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: AppleIntelligenceTextField(
              controller: c,
              initialText: 'the quick brown fox',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(c.isAttached, isTrue, reason: 'platform view never called back');

    final TextCapabilities caps = await c.capabilities();
    // ignore: avoid_print
    print('  capabilities: $caps');
    expect(caps.writingTools, isTrue);
    expect(caps.genmoji, isTrue);

    expect(await c.getText(), 'the quick brown fox');
    await c.setText('rewritten');
    expect(await c.getText(), 'rewritten');
    // ignore: avoid_print
    print('  round-trip through the native view: ok');
  });
}
