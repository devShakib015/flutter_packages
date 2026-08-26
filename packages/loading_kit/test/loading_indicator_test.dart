import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';
// Reaching into src is deliberate: the painter is the thing under test.
import 'package:loading_kit/src/painting/loading_indicator_painter.dart';

void main() {
  LoadingIndicatorPainter painterOf(WidgetTester tester) {
    return tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(LoadingIndicator),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as LoadingIndicatorPainter;
  }

  Widget host(Widget child) => MaterialApp(
    home: Material(child: Center(child: child)),
  );

  testWidgets('the indeterminate arc advances between frames', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const LoadingIndicator()));

    final double first = painterOf(tester).spin;
    await tester.pump(const Duration(milliseconds: 200));
    final double second = painterOf(tester).spin;
    await tester.pump(const Duration(milliseconds: 200));
    final double third = painterOf(tester).spin;

    // A painter that snapshots its animation values must be rebuilt per frame.
    // Handing CustomPaint a `repaint` listenable instead re-runs paint() on a
    // frozen instance, which renders a completely motionless spinner while
    // every other test still passes.
    expect(second, isNot(first), reason: 'the arc must move');
    expect(third, isNot(second), reason: 'and keep moving');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('settling stops the ticker instead of spinning forever', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const LoadingIndicator()));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(
      host(const LoadingIndicator(status: LoadingStatus.success)),
    );
    await tester.pump(const Duration(milliseconds: 700));

    final double settled = painterOf(tester).spin;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      painterOf(tester).spin,
      settled,
      reason: 'a settled indicator should not burn frames',
    );
    expect(painterOf(tester).morph, 1.0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('determinate progress is interpolated, not snapped', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const LoadingIndicator(progress: 0)));
    await tester.pumpWidget(host(const LoadingIndicator(progress: 1)));

    await tester.pump(const Duration(milliseconds: 120));
    final double mid = painterOf(tester).progress!;
    expect(mid, greaterThan(0.0));
    expect(mid, lessThan(1.0), reason: 'coarse jumps animate across');

    await tester.pump(const Duration(milliseconds: 400));
    expect(painterOf(tester).progress, moreOrLessEquals(1.0, epsilon: 0.001));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
