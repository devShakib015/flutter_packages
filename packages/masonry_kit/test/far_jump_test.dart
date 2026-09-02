// The catch-up walk releases children it has already passed. These guard the
// correctness of that release: dropping the wrong ones would misplace items or
// restart the walk from zero.
//
// Measured effect on a 2,000-item grid jumped to 90%: peak live children fell
// from 1,808 to 118, with the same 1,790 builder calls — the measurement work
// is inherent to sequential masonry, holding all of it in memory was not.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

Future<ScrollController> longGrid(WidgetTester tester, int n) async {
  final ScrollController sc = ScrollController();
  addTearDown(sc.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: CustomScrollView(
            controller: sc,
            slivers: <Widget>[
              SliverMasonryGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childCount: n,
                itemBuilder: (BuildContext c, int i) =>
                    SizedBox(height: h(i), child: Text('i$i')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sc;
}

void main() {
  testWidgets('a far jump lands somewhere real and holds few children', (
    WidgetTester tester,
  ) async {
    final ScrollController sc = await longGrid(tester, 2000);
    final double target = sc.position.maxScrollExtent * 0.9;
    sc.jumpTo(target);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(sc.offset, closeTo(target, 1));

    final RenderSliverMultiBoxAdaptor sliver =
        tester.renderObject<RenderSliverMultiBoxAdaptor>(
      find.byType(SliverMasonryGrid),
    );
    // Whatever the walk held on the way, only a window survives it.
    expect(sliver.childCount, lessThan(80));
    expect(find.textContaining('i'), findsWidgets);
  });

  testWidgets('placements after a far jump match placements walked to', (
    WidgetTester tester,
  ) async {
    // The release must not disturb the cache. Jumping to an offset and
    // scrolling to the same offset have to agree about what is on screen —
    // that is the never-revise contract, and it is what the release could
    // plausibly break.
    final ScrollController jumped = await longGrid(tester, 300);
    final double target = jumped.position.maxScrollExtent * 0.6;
    jumped.jumpTo(target);
    await tester.pumpAndSettle();
    final List<String> afterJump = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data!)
        .toList()
      ..sort();

    final ScrollController walked = await longGrid(tester, 300);
    for (double at = 0; at < target; at += 300) {
      walked.jumpTo(at);
      await tester.pumpAndSettle();
    }
    walked.jumpTo(target);
    await tester.pumpAndSettle();
    final List<String> afterWalk = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text t) => t.data!)
        .toList()
      ..sort();

    expect(afterJump, afterWalk);
  });

  testWidgets('jumping back to the top still works', (
    WidgetTester tester,
  ) async {
    // The children covering the top were released on the way out; going back
    // has to rebuild them rather than show a hole.
    final ScrollController sc = await longGrid(tester, 800);
    sc.jumpTo(sc.position.maxScrollExtent * 0.8);
    await tester.pumpAndSettle();
    sc.jumpTo(0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('i0'), findsOneWidget);
    expect(sc.offset, 0);
  });
}
