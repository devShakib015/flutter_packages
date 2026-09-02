// The README makes a numeric claim about the package this one replaces.
// This is that claim, executed, so it cannot quietly stop being true.
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'
    as incumbent;
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart' as kit;

double h(int i) => 60.0 + (i * 37) % 90;
Widget cell(int seed, int i) =>
    SizedBox(height: h(i + seed), child: Text('s$seed-i$i'));

Widget oldGrid(int seed, int n) => incumbent.SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childCount: n,
      itemBuilder: (BuildContext c, int i) => cell(seed, i),
    );

Widget newGrid(int seed, int n) => kit.SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childCount: n,
      itemBuilder: (BuildContext c, int i) => cell(seed, i),
    );

/// Drags forward 45 times and reports how far the viewport ever went
/// backwards, which is the thing users notice.
Future<({int jumps, double worst})> walk(
  WidgetTester tester,
  List<Widget> slivers,
) async {
  final ScrollController sc = ScrollController();
  addTearDown(sc.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(controller: sc, slivers: slivers),
      ),
    ),
  );
  await tester.pumpAndSettle();
  double previous = sc.offset;
  double worst = 0;
  int jumps = 0;
  for (int i = 0; i < 45; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    if (sc.offset < previous - 1) {
      jumps++;
      if (previous - sc.offset > worst) worst = previous - sc.offset;
    }
    previous = sc.offset;
  }
  return (jumps: jumps, worst: worst);
}

/// Drags forward through one long grid and reports the worst *shrink* in the
/// reported scroll extent.
///
/// A lazy sliver has to estimate the extent of everything it has not measured
/// yet. When that estimate is revised downward the total scroll range shrinks
/// under the user's finger, and the scrollbar thumb jumps and resizes while
/// they are dragging it. Measured items contributing their exact extent is
/// what keeps that number small.
Future<double> drift(WidgetTester tester, Widget sliver) async {
  final ScrollController sc = ScrollController();
  addTearDown(sc.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CustomScrollView(controller: sc, slivers: <Widget>[sliver]),
      ),
    ),
  );
  await tester.pumpAndSettle();

  double previous = sc.position.maxScrollExtent;
  double worst = 0;
  for (int i = 0; i < 45; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    final double now = sc.position.maxScrollExtent;
    if (previous - now > worst) worst = previous - now;
    previous = now;
  }
  return worst;
}

/// A plain SliverList over the same cells, as the reference point: this is
/// what Flutter's own lazy estimation does, so it is the bar to beat.
Widget referenceList(int n) => SliverList.builder(
      itemCount: n,
      itemBuilder: (BuildContext c, int i) => cell(0, i),
    );

void main() {
  group('two grids in one CustomScrollView', () {
    testWidgets(
        'the incumbent still jumps — if this fails, it was fixed '
        'upstream and the README needs revisiting', (
      WidgetTester tester,
    ) async {
      final ({int jumps, double worst}) r = await walk(tester, <Widget>[
        oldGrid(0, 60),
        oldGrid(500, 60),
      ]);
      expect(r.jumps, greaterThan(0));
      expect(r.worst, greaterThan(1000));
    });

    testWidgets('masonry_kit does not', (WidgetTester tester) async {
      final ({int jumps, double worst}) r = await walk(tester, <Widget>[
        newGrid(0, 60),
        newGrid(500, 60),
      ]);
      expect(r.jumps, 0, reason: 'worst ${r.worst}px');
    });
  });

  group('four grids', () {
    testWidgets('the incumbent still jumps', (WidgetTester tester) async {
      final ({int jumps, double worst}) r = await walk(tester, <Widget>[
        oldGrid(0, 40),
        oldGrid(300, 40),
        oldGrid(600, 40),
        oldGrid(900, 40),
      ]);
      expect(r.jumps, greaterThan(0));
    });

    testWidgets('masonry_kit does not', (WidgetTester tester) async {
      final ({int jumps, double worst}) r = await walk(tester, <Widget>[
        newGrid(0, 40),
        newGrid(300, 40),
        newGrid(600, 40),
        newGrid(900, 40),
      ]);
      expect(r.jumps, 0, reason: 'worst ${r.worst}px');
    });
  });

  group('scrollbar honesty — the README quotes these numbers', () {
    // One subject per test, deliberately. Measuring all three inside a single
    // test body pumps three widget trees into the same tester and the later
    // measurements come out wrong — SliverList read 1,546px instead of 2,887
    // and masonry_kit read 0 instead of 145. Each subject gets a clean tester.
    const int items = 400;

    testWidgets('the incumbent revises its estimate hard', (
      WidgetTester tester,
    ) async {
      final double d = await drift(tester, oldGrid(0, items));
      // ignore: avoid_print
      print('DRIFT incumbent=${d.round()}');
      expect(d, greaterThan(1000), reason: '${d.round()}px');
    });

    testWidgets("Flutter's own SliverList revises it too", (
      WidgetTester tester,
    ) async {
      // The reference point, and not a flattering one for the incumbent: the
      // framework's plain lazy estimate drifts further than either grid here.
      final double d = await drift(tester, referenceList(items));
      // ignore: avoid_print
      print('DRIFT sliverList=${d.round()}');
      expect(d, greaterThan(1000), reason: '${d.round()}px');
    });

    testWidgets('masonry_kit barely moves', (WidgetTester tester) async {
      // Measured 145px against 1,920 and 2,887. The bound is deliberately
      // loose: the absolute figure depends on item count, cell heights and
      // drag distance, but an order of magnitude of headroom is the claim.
      final double d = await drift(tester, newGrid(0, items));
      // ignore: avoid_print
      print('DRIFT masonryKit=${d.round()}');
      expect(d, lessThan(400), reason: '${d.round()}px');
    });
  });
}
