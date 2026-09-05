// The example is a multi-view app, so its smoke test needs the multi-view
// root: wrapWithView: false, because DocumentPipApp owns the views itself.
import 'package:document_pip_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the page renders and offers the pop-out', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildApp(), wrapWithView: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('document_pip'), findsOneWidget);
    expect(find.text('Pop out'), findsOneWidget);
    // Off-web the button is disabled rather than absent, and the reason is on
    // screen instead of hidden behind a click that would always fail.
    expect(find.textContaining('Document Picture-in-Picture'), findsOneWidget);
  });
}
