// Each test pins a defect found by the 2026-09-02 audit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

void main() {
  testWidgets('a tile that dirties itself is still painted', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.2.0: children are laid out loose on the main axis with
    // parentUsesSize, so none is a relayout boundary. A tile that dirtied
    // itself — a network image resolving, a font arriving, its own setState —
    // marked the sliver dirty but was then SKIPPED by the relayout walk, so
    // it stayed _needsLayout and the framework refused to paint it. The tile
    // simply vanished.
    final GlobalKey<_GrowState> grower = GlobalKey<_GrowState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: <Widget>[
              SliverMasonryGrid.count(
                crossAxisCount: 2,
                childCount: 12,
                itemBuilder: (BuildContext c, int i) => i == 3
                    ? _Grow(key: grower)
                    : SizedBox(height: 60 + (i % 3) * 20, child: Text('t$i')),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('grown-no'), findsOneWidget);

    grower.currentState!.grow();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Before the fix this found nothing: the tile was laid out but never
    // painted, so its subtree was skipped entirely.
    expect(find.text('grown-yes'), findsOneWidget);
  });

  testWidgets('an ancestor rebuild does not re-measure from index 0', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.2.0: invalidation keyed off delegate.shouldRebuild, which
    // SliverChildBuilderDelegate hardcodes to true. So ANY ancestor rebuild —
    // a theme change, a parent setState — threw away every placement and
    // every live child, and the next layout walked from index 0 rebuilding
    // every item up to the window. Invisible at the top of the list, brutal
    // once the reader has scrolled.
    final Set<int> built = <int>{};
    late StateSetter setOuter;
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext ctx, StateSetter set) {
              setOuter = set;
              return CustomScrollView(
                controller: scroll,
                slivers: <Widget>[
                  SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    childCount: 400,
                    itemBuilder: (BuildContext c, int i) {
                      built.add(i);
                      return SizedBox(
                        height: 50 + (i % 4) * 15,
                        child: Text('t$i'),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    scroll.jumpTo(4000);
    await tester.pumpAndSettle();

    built.clear();
    setOuter(() {});
    await tester.pumpAndSettle();

    expect(
      built,
      isNot(contains(0)),
      reason: 'a parent setState re-measured the list from the very start',
    );
    expect(
      built.length,
      lessThan(60),
      reason: 'a rebuild should touch the window, not everything before it',
    );
  });

  testWidgets('columns mirror under RTL', (WidgetTester tester) async {
    // Shipped in 0.2.0: constraints.crossAxisDirection was ignored, so
    // column 0 stayed on the left under TextDirection.rtl while paint()
    // applies a fixed cross-axis unit vector.
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: CustomScrollView(
              slivers: <Widget>[
                SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  childCount: 6,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: 60, child: Text('t$i')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final double t0 = tester.getTopLeft(find.text('t0')).dx;
    final double width = tester.getSize(find.byType(CustomScrollView)).width;
    expect(
      t0,
      greaterThanOrEqualTo(width / 2),
      reason: 'under RTL the first column belongs on the right',
    );
  });

  testWidgets('spacing wider than the viewport does not throw', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.2.0: crossAxisExtent - spacing * (columns - 1) went
    // negative and reached BoxConstraints.tightFor, which asserts.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 40,
            child: CustomScrollView(
              slivers: <Widget>[
                SliverMasonryGrid.count(
                  crossAxisCount: 4,
                  crossAxisSpacing: 200,
                  childCount: 4,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: 40, child: Text('t$i')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _Grow extends StatefulWidget {
  const _Grow({super.key});
  @override
  State<_Grow> createState() => _GrowState();
}

class _GrowState extends State<_Grow> {
  bool _grown = false;

  /// Stands in for an image resolving or a font arriving: the tile changes its
  /// own size after the sliver has already measured it once.
  void grow() => setState(() => _grown = true);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _grown ? 180 : 60,
        child: Text(_grown ? 'grown-yes' : 'grown-no'),
      );
}
