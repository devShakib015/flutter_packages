import 'dart:math' as math;

import 'package:fit_text/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Material's bodyMedium carries letterSpacing and a height multiplier, so the
  // widget would measure differently from the helper below. Pinning a plain
  // style keeps the invariant checks exact.
  const TextStyle base = TextStyle(fontSize: 14);

  Widget box(Widget child, {double width = 200, double? height}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: DefaultTextStyle(
          style: base,
          child: SizedBox(width: width, height: height, child: child),
        ),
      ),
    ),
  );

  RenderFitText render(WidgetTester tester) =>
      tester.renderObject<RenderFitText>(find.byType(FitText));

  double fitted(WidgetTester tester) => render(tester).fittedFontSize;

  /// Measures with the same engine the widget uses, so assertions hold
  /// whatever font the test environment supplies.
  double widthAt(String text, double fontSize, {int? maxLines}) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: base.copyWith(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout();
    final double width = painter.width;
    painter.dispose();
    return width;
  }

  /// The invariant the whole package rests on: the chosen size fits, and one
  /// step larger would not.
  void expectLargestFitting(
    WidgetTester tester,
    String text,
    double boxWidth, {
    double step = 1,
  }) {
    final double size = fitted(tester);
    expect(
      widthAt(text, size),
      lessThanOrEqualTo(boxWidth + 0.01),
      reason: 'the chosen size $size must fit',
    );
    expect(
      widthAt(text, size + step),
      greaterThan(boxWidth + 0.01),
      reason: 'one step above $size should not have fitted',
    );
  }

  group('the reason this package exists', () {
    testWidgets('works inside IntrinsicHeight, where LayoutBuilder throws', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(
          IntrinsicHeight(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: FitText(
                    '0123456789',
                    maxLines: 1,
                    minFontSize: 4,
                    maxFontSize: 100,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(fitted(tester), greaterThan(4.0));
      expect(render(tester).didOverflow, isFalse);
    });

    testWidgets('works inside IntrinsicWidth', (WidgetTester tester) async {
      await tester.pumpWidget(
        box(
          IntrinsicWidth(
            child: FitText(
              '0123456789',
              maxLines: 1,
              minFontSize: 4,
              maxFontSize: 40,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('works in a Table cell', (WidgetTester tester) async {
      // Table sizes columns with intrinsics, the other place a
      // LayoutBuilder-based widget cannot go.
      await tester.pumpWidget(
        box(
          Table(
            children: const <TableRow>[
              TableRow(
                children: <Widget>[
                  FitText(
                    '0123456789',
                    maxLines: 1,
                    minFontSize: 4,
                    maxFontSize: 40,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FitText), findsOneWidget);
    });

    testWidgets('works under baseline alignment', (WidgetTester tester) async {
      await tester.pumpWidget(
        box(
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const <Widget>[
              Text('anchor'),
              Expanded(
                child: FitText(
                  '0123456789',
                  maxLines: 1,
                  minFontSize: 4,
                  maxFontSize: 40,
                ),
              ),
            ],
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'baseline alignment queries the baseline during layout',
      );
    });

    testWidgets('for contrast, a bare LayoutBuilder still throws there', (
      WidgetTester tester,
    ) async {
      // Pinned so the motivating limitation lives in the suite, not just the
      // README. If Flutter ever lifts it, this test says so.
      final List<FlutterErrorDetails> errors = <FlutterErrorDetails>[];
      final void Function(FlutterErrorDetails)? previous = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        box(
          IntrinsicHeight(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: LayoutBuilder(
                    builder: (BuildContext c, BoxConstraints k) =>
                        const Text('x'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      FlutterError.onError = previous;
      tester.takeException();
      expect(
        errors.map((FlutterErrorDetails e) => e.exceptionAsString()).join(),
        contains('does not support returning intrinsic dimensions'),
      );
    });
  });

  group('fitting', () {
    testWidgets('picks the largest size that fits', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(FitText('01234', maxLines: 1, minFontSize: 4, maxFontSize: 100)),
      );
      expectLargestFitting(tester, '01234', 200);
    });

    testWidgets('is bounded by maxFontSize', (WidgetTester tester) async {
      await tester.pumpWidget(
        box(FitText('01', maxLines: 1, minFontSize: 4, maxFontSize: 30)),
      );
      expect(fitted(tester), 30.0, reason: 'would fit larger, capped at 30');
    });

    testWidgets('respects a height constraint', (WidgetTester tester) async {
      await tester.pumpWidget(
        box(
          FitText('01234', maxLines: 1, minFontSize: 4, maxFontSize: 100),
          height: 12,
        ),
      );
      expect(render(tester).size.height, lessThanOrEqualTo(12.0));
    });

    testWidgets('stops at minFontSize and reports the overflow', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(
          FitText('0123456789' * 10, maxLines: 1, minFontSize: 10),
          width: 50,
        ),
      );
      expect(fitted(tester), 10.0);
      expect(render(tester).didOverflow, isTrue);
    });

    testWidgets('lands on a stepGranularity boundary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(
          FitText(
            '0123456789',
            maxLines: 1,
            minFontSize: 5,
            maxFontSize: 100,
            stepGranularity: 7,
          ),
        ),
      );
      final double size = fitted(tester);
      expect(
        (size - 5) % 7,
        moreOrLessEquals(0, epsilon: 0.001),
        reason: 'got $size, which is not 5 + 7n',
      );
      expectLargestFitting(tester, '0123456789', 200, step: 7);
    });

    testWidgets('chooses from presetFontSizes only', (
      WidgetTester tester,
    ) async {
      const List<double> scale = <double>[8, 14, 32, 64];
      await tester.pumpWidget(
        box(FitText('0123456789', maxLines: 1, presetFontSizes: scale)),
      );
      final double size = fitted(tester);
      expect(scale, contains(size));
      expect(widthAt('0123456789', size), lessThanOrEqualTo(200.01));
    });

    testWidgets('two lines allow a larger size than one', (
      WidgetTester tester,
    ) async {
      Future<double> sizeWith(int maxLines) async {
        await tester.pumpWidget(
          box(
            FitText(
              '01234 56789',
              maxLines: maxLines,
              minFontSize: 4,
              maxFontSize: 100,
            ),
          ),
        );
        return fitted(tester);
      }

      expect(await sizeWith(2), greaterThan(await sizeWith(1)));
    });
  });

  group('constraints', () {
    testWidgets('unbounded width grows to maxFontSize', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: const <Widget>[
                FitText('01', maxLines: 1, minFontSize: 4, maxFontSize: 42),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(fitted(tester), 42.0);
    });

    testWidgets('dry layout agrees with real layout', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(FitText('01234', maxLines: 1, minFontSize: 4, maxFontSize: 100)),
      );
      final RenderFitText r = render(tester);
      expect(
        r.getDryLayout(r.constraints).width,
        moreOrLessEquals(r.size.width, epsilon: 0.01),
      );
    });

    testWidgets('re-fits when the box changes', (WidgetTester tester) async {
      await tester.pumpWidget(
        box(FitText('01234', maxLines: 1, minFontSize: 4, maxFontSize: 100)),
      );
      final double wide = fitted(tester);

      await tester.pumpWidget(
        box(
          FitText('01234', maxLines: 1, minFontSize: 4, maxFontSize: 100),
          width: 100,
        ),
      );
      final double narrow = fitted(tester);

      expect(narrow, lessThan(wide));
      expectLargestFitting(tester, '01234', 100);
    });
  });

  group('groups', groupTests);

  group('api', () {
    testWidgets('inherits DefaultTextStyle as the ceiling', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(
          DefaultTextStyle(
            style: const TextStyle(fontSize: 11),
            child: FitText('01', maxLines: 1),
          ),
        ),
      );
      expect(
        fitted(tester),
        11.0,
        reason: 'an unbounded ceiling falls back to the inherited size',
      );
    });

    testWidgets('exposes a semantics label', (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(box(FitText('hello', maxLines: 1)));
      expect(tester.getSemantics(find.byType(FitText)).label, 'hello');
      handle.dispose();
    });

    testWidgets('FitText.rich scales nested spans proportionally', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        box(
          const FitText.rich(
            TextSpan(
              text: '01',
              style: TextStyle(fontSize: 50),
              children: <InlineSpan>[
                TextSpan(text: '234', style: TextStyle(fontSize: 25)),
              ],
            ),
            maxLines: 1,
            minFontSize: 4,
            maxFontSize: 100,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(render(tester).didOverflow, isFalse);
      expect(render(tester).size.width, lessThanOrEqualTo(200.01));
    });

    testWidgets('both constructors are const', (WidgetTester tester) async {
      // Guards the ergonomics: Text is const, so FitText must be too.
      const FitText plain = FitText('x');
      const FitText rich = FitText.rich(TextSpan(text: 'x'));
      await tester.pumpWidget(
        box(const Column(children: <Widget>[plain, rich])),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejects impossible configuration', (
      WidgetTester tester,
    ) async {
      expect(() => FitText('x', minFontSize: 0), throwsAssertionError);
      expect(
        () => FitText('x', minFontSize: 40, maxFontSize: 10),
        throwsAssertionError,
      );
      expect(() => FitText('x', stepGranularity: 0), throwsAssertionError);
      expect(() => FitText('x', maxLines: 0), throwsAssertionError);
    });
  });
}

/// Group behaviour, which is what makes migrating from the incumbent possible.
void groupTests() {
  Widget row(List<String> labels, {FitTextGroup? group}) => MaterialApp(
    home: Scaffold(
      body: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: SizedBox(
          width: 300,
          child: Row(
            children: <Widget>[
              for (final String label in labels)
                Expanded(
                  child: FitText(
                    label,
                    key: ValueKey<String>(label),
                    group: group,
                    maxLines: 1,
                    minFontSize: 4,
                    maxFontSize: 60,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  List<double> sizes(WidgetTester tester) => tester
      .renderObjectList<RenderFitText>(find.byType(FitText))
      .map((RenderFitText r) => r.fittedFontSize)
      .toList();

  const List<String> labels = <String>['Ok', 'Discard everything'];

  testWidgets('members converge on the smallest size any of them needed', (
    WidgetTester tester,
  ) async {
    // What each would choose alone, in the same layout.
    await tester.pumpWidget(row(labels));
    final List<double> independent = sizes(tester);
    expect(
      independent.toSet(),
      hasLength(2),
      reason: 'without a group they should differ, got $independent',
    );
    final double smallest = independent.reduce(math.min);

    final FitTextGroup group = FitTextGroup();
    await tester.pumpWidget(row(labels, group: group));
    // Members find their own size first and agree on the next frame.
    await tester.pump();
    await tester.pump();

    expect(
      sizes(tester),
      everyElement(smallest),
      reason: 'all members should take the constrained size $smallest',
    );
    expect(group.resolvedFontSize, smallest);
  });

  testWidgets('a removed member releases its constraint', (
    WidgetTester tester,
  ) async {
    final FitTextGroup group = FitTextGroup();
    await tester.pumpWidget(row(labels, group: group));
    await tester.pump();
    await tester.pump();
    expect(group.length, 2);

    await tester.pumpWidget(row(const <String>['Ok'], group: group));
    await tester.pump();
    await tester.pump();

    expect(group.length, 1, reason: 'the disposed member should be gone');
    expect(sizes(tester).first, greaterThan(group.resolvedFontSize! - 0.001));
  });

  testWidgets('no group means no coordination', (WidgetTester tester) async {
    await tester.pumpWidget(row(labels));
    expect(sizes(tester).toSet(), hasLength(2));
  });
}
