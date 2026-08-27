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

void main() {
  group('two grids in one CustomScrollView', () {
    testWidgets('the incumbent still jumps — if this fails, it was fixed '
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
}
