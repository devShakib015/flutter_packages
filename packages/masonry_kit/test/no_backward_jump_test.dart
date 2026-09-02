import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

Widget grid(int seed, int n) => SliverMasonryGrid.count(
      crossAxisCount: 2,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      childCount: n,
      itemBuilder: (BuildContext c, int i) =>
          SizedBox(height: h(i + seed), child: Text('s$seed-i$i')),
    );

/// Drag forward repeatedly. A correct sliver never moves the viewport
/// backwards while the finger is going forwards. This is the exact
/// measurement that flutter_staggered_grid_view fails, twice, by up to
/// 3,400px — issue #265 on its tracker, open since 2022.
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
      worst = (previous - sc.offset) > worst ? previous - sc.offset : worst;
    }
    previous = sc.offset;
  }
  return (jumps: jumps, worst: worst);
}

void main() {
  testWidgets('one grid never goes backwards', (WidgetTester tester) async {
    final ({int jumps, double worst}) r = await walk(tester, <Widget>[
      grid(0, 120),
    ]);
    expect(r.jumps, 0, reason: 'worst regression ${r.worst}px');
  });

  testWidgets('two grids in one CustomScrollView never go backwards', (
    WidgetTester tester,
  ) async {
    final ({int jumps, double worst}) r = await walk(tester, <Widget>[
      grid(0, 60),
      grid(500, 60),
    ]);
    expect(r.jumps, 0, reason: 'worst regression ${r.worst}px');
  });

  testWidgets('four grids interleaved with other slivers', (
    WidgetTester tester,
  ) async {
    final ({int jumps, double worst}) r = await walk(tester, <Widget>[
      grid(0, 40),
      const SliverToBoxAdapter(child: SizedBox(height: 60, child: Text('—'))),
      grid(300, 40),
      SliverList.builder(
        itemCount: 10,
        itemBuilder: (BuildContext c, int i) => SizedBox(height: 40),
      ),
      grid(600, 40),
      grid(900, 40),
    ]);
    expect(r.jumps, 0, reason: 'worst regression ${r.worst}px');
  });
}
