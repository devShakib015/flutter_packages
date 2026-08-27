import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

void main() {
  Widget host(Widget child, {Size size = const Size(300, 500)}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  testWidgets('a scrollbar-style jump lands somewhere sane', (
    WidgetTester tester,
  ) async {
    final ScrollController sc = ScrollController();
    addTearDown(sc.dispose);
    await tester.pumpWidget(
      host(
        MasonryGridView.count(
          crossAxisCount: 2,
          controller: sc,
          itemCount: 400,
          itemBuilder: (BuildContext c, int i) =>
              SizedBox(height: h(i), child: Text('i$i')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    sc.jumpTo(sc.position.maxScrollExtent * 0.5);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    sc.jumpTo(sc.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Everything is measured by now, so the end is the true end.
    expect(find.text('i399'), findsOneWidget);
  });

  testWidgets('zero-height items do not stall the layout', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        MasonryGridView.count(
          crossAxisCount: 3,
          itemCount: 200,
          itemBuilder: (BuildContext c, int i) =>
              SizedBox(height: i.isEven ? 0 : 50, child: Text('i$i')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('i1'), findsOneWidget);
  });

  testWidgets('repeated resizes stay consistent', (WidgetTester tester) async {
    Widget build(double width) => host(
      MasonryGridView.count(
        crossAxisCount: 2,
        itemCount: 80,
        itemBuilder: (BuildContext c, int i) =>
            SizedBox(height: h(i), child: Text('i$i')),
      ),
      size: Size(width, 500),
    );
    for (final double w in <double>[300, 200, 420, 300, 150, 300]) {
      await tester.pumpWidget(build(w));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // Back at 300 the layout should match a fresh 300-wide build.
    final Rect resized = tester.getRect(find.text('i2'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(build(300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('i2')), resized);
  });

  testWidgets('a hundred thousand items still builds a screenful', (
    WidgetTester tester,
  ) async {
    int built = 0;
    await tester.pumpWidget(
      host(
        MasonryGridView.count(
          crossAxisCount: 2,
          itemCount: 100000,
          itemBuilder: (BuildContext c, int i) {
            built++;
            return SizedBox(height: h(i), child: Text('i$i'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built, lessThan(60), reason: 'built $built');
  });

  testWidgets('scroll extent never shrinks while scrolling forward', (
    WidgetTester tester,
  ) async {
    final ScrollController sc = ScrollController();
    addTearDown(sc.dispose);
    await tester.pumpWidget(
      host(
        MasonryGridView.count(
          crossAxisCount: 2,
          controller: sc,
          itemCount: 300,
          itemBuilder: (BuildContext c, int i) =>
              SizedBox(height: h(i), child: Text('i$i')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double worstShrink = 0;
    double peak = sc.position.maxScrollExtent;
    for (int i = 0; i < 40; i++) {
      await tester.drag(find.byType(MasonryGridView), const Offset(0, -280));
      await tester.pumpAndSettle();
      final double max = sc.position.maxScrollExtent;
      if (max > peak) peak = max;
      if (peak - max > worstShrink) worstShrink = peak - max;
    }
    // An estimate that only improves is what keeps the scrollbar honest.
    // Flutter's own SliverList drifts by a few hundred px here.
    expect(worstShrink, lessThan(400), reason: 'shrank ${worstShrink}px');
  });
}
