// A masonry sliver sitting entirely below the viewport's cache region used to
// report SliverGeometry.zero, so maxScrollExtent left it out and the scrollbar
// under-reported the page until the reader scrolled near it. That shows up in
// exactly the arrangement this package exists for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

Widget grid(String tag, int n) => SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childCount: n,
      itemBuilder: (BuildContext c, int i) =>
          SizedBox(height: h(i), child: Text('$tag$i')),
    );

void main() {
  testWidgets('a second grid far below is counted before it is reached', (
    WidgetTester tester,
  ) async {
    final ScrollController sc = ScrollController();
    addTearDown(sc.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              controller: sc,
              slivers: <Widget>[grid('a', 200), grid('b', 200)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final double both = sc.position.maxScrollExtent;

    // The first grid alone, for comparison.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              controller: ScrollController(),
              slivers: <Widget>[grid('a', 200)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final ScrollableState state = tester.state(find.byType(Scrollable));
    final double justOne = state.position.maxScrollExtent;

    // Two grids must claim materially more room than one. Before the fix the
    // second contributed nothing at all until it came near the cache window.
    expect(
      both,
      greaterThan(justOne * 1.5),
      reason: 'two grids $both vs one $justOne',
    );
  });

  testWidgets('an empty sliver still reports nothing', (
    WidgetTester tester,
  ) async {
    // The estimate must not turn a genuinely empty grid into a phantom.
    final ScrollController sc = ScrollController();
    addTearDown(sc.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              controller: sc,
              slivers: <Widget>[grid('a', 20), grid('empty', 0)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('a0'), findsOneWidget);
  });

  testWidgets('scrolling into the far grid still lands correctly', (
    WidgetTester tester,
  ) async {
    // The estimate is replaced by real measurements as the reader arrives;
    // it must not leave the viewport somewhere impossible on the way.
    final ScrollController sc = ScrollController();
    addTearDown(sc.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: CustomScrollView(
              controller: sc,
              slivers: <Widget>[grid('a', 60), grid('b', 60)],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double previous = sc.offset;
    int jumps = 0;
    for (int i = 0; i < 40; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      if (sc.offset < previous - 1) jumps++;
      previous = sc.offset;
    }
    expect(jumps, 0, reason: 'the estimate must not cause a correction');
    expect(find.textContaining('b'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
