// Each test pins a defect found by the 2026-09-02 audit.
import 'package:fit_text/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a tap on FitText reaches the GestureDetector around it', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.3: RenderFitText never reported a hit, so every
    // GestureDetector wrapping a FitText and every TextSpan.recognizer inside
    // one was silently dead. RenderParagraph implements hitTestSelf; this did
    // not.
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => taps++,
              child: const SizedBox(
                width: 200,
                height: 60,
                child: FitText('tap me'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FitText));
    expect(taps, 1);
  });

  testWidgets('IntrinsicHeight around a baseline Row does not throw', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.3: computeDryBaseline was not overridden, so the
    // framework fell back to a real layout to answer a dry baseline query and
    // asserted. Working inside IntrinsicHeight is the reason this package
    // exists — auto_size_text cannot, and that is the README's headline.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: const <Widget>[
                  SizedBox(width: 120, child: FitText('fitted')),
                  Text('plain'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('overflowing text with fade stays inside its own box', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.3: TextOverflow.fade was a complete no-op, so text that
    // did not fit at minFontSize painted straight over its neighbours.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: 20,
              child: FitText(
                'a very long line that cannot possibly fit in sixty pixels',
                minFontSize: 14,
                maxFontSize: 14,
                overflow: TextOverflow.fade,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(FitText)), const Size(60, 20));
  });

  testWidgets('a WidgetSpan is refused by name, not from inside TextPainter', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 60,
            child: FitText.rich(
              const TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: 'before '),
                  WidgetSpan(child: Icon(Icons.star)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final Object? thrown = tester.takeException();
    expect(thrown, isAssertionError);
    expect(thrown.toString(), contains('FitText.rich'));
  });
}
