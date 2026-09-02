// Each test pins a defect found by the 2026-09-02 audit.
import 'dart:async';

import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host({
    required List<String> items,
    required AnchoredListController controller,
    int initialIndex = 0,
    double initialAlignment = 0,
    bool reverse = false,
    EdgeInsets? padding,
    Widget Function(BuildContext, int)? itemBuilder,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: AnchoredList.builder(
              controller: controller,
              itemCount: items.length,
              initialIndex: initialIndex,
              initialAlignment: initialAlignment,
              reverse: reverse,
              padding: padding,
              itemBuilder: itemBuilder ??
                  (BuildContext c, int i) =>
                      SizedBox(height: 50, child: Text(items[i])),
            ),
          ),
        ),
      );

  group('a prepend is never dropped, wherever the anchor sits', () {
    testWidgets('anchored at the very last item', (WidgetTester tester) async {
      // Shipped in 0.1.1: shiftAnchor clamped the new anchor against
      // widget.itemCount, which is still the OLD count between the caller's
      // setState and the rebuild. Anchored at the end — a chat pinned to the
      // newest message, the flagship case — the shift was clamped away
      // entirely and the reader's content slid down the screen.
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      final List<String> items = List<String>.generate(50, (int i) => 'm$i');

      late StateSetter setOuter;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: StatefulBuilder(
                builder: (BuildContext ctx, StateSetter set) {
                  setOuter = set;
                  return AnchoredList.builder(
                    controller: c,
                    itemCount: items.length,
                    initialIndex: items.length - 1,
                    itemBuilder: (BuildContext c2, int i) =>
                        SizedBox(height: 50, child: Text(items[i])),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.anchorIndex, 49);

      setOuter(() => items.insertAll(0, <String>['a', 'b', 'c', 'd', 'e']));
      c.itemsInsertedAbove(5);
      await tester.pumpAndSettle();

      // The same message must still be the anchor: index 49 became index 54.
      expect(c.anchorIndex, 54);
    });

    testWidgets('anchored in the middle, as the old tests did', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      final List<String> items = List<String>.generate(50, (int i) => 'm$i');

      late StateSetter setOuter;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: StatefulBuilder(
                builder: (BuildContext ctx, StateSetter set) {
                  setOuter = set;
                  return AnchoredList.builder(
                    controller: c,
                    itemCount: items.length,
                    initialIndex: 20,
                    itemBuilder: (BuildContext c2, int i) =>
                        SizedBox(height: 50, child: Text(items[i])),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      setOuter(() => items.insertAll(0, <String>['a', 'b', 'c']));
      c.itemsInsertedAbove(3);
      await tester.pumpAndSettle();
      expect(c.anchorIndex, 23);
    });
  });

  testWidgets('an item with a GlobalKey does not crash the list', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.1: the child's key was copied onto the wrapper, so two
    // live elements registered the same GlobalKey and Flutter threw
    // "Multiple widgets used the same GlobalKey" on the first frame.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);
    final GlobalKey itemKey = GlobalKey();

    await tester.pumpWidget(
      host(
        items: List<String>.generate(20, (int i) => 'm$i'),
        controller: c,
        itemBuilder: (BuildContext ctx, int i) => SizedBox(
          key: i == 2 ? itemKey : ValueKey<int>(i),
          height: 50,
          child: Text('m$i'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(itemKey.currentContext, isNotNull);
  });

  testWidgets('reverse: true does not double the padding at the anchor', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.1: the split chose a physical side from the scroll axis
    // alone, ignoring reverse. Under reverse the anchor-facing edges were the
    // ones kept, so a padded chat got a blank gap in the middle of its
    // content and nothing at either end.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      host(
        items: List<String>.generate(30, (int i) => 'm$i'),
        controller: c,
        initialIndex: 15,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 24),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The two rows either side of the anchor must sit one row apart, with no
    // padding wedged between them.
    final double m15 = tester.getTopLeft(find.text('m15')).dy;
    final double m16 = tester.getTopLeft(find.text('m16')).dy;
    expect((m15 - m16).abs(), closeTo(50, 0.5));
  });

  testWidgets('jumpToIndex aligns the box, matching animateToIndex', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.1: alignment placed the item's LEADING EDGE, so 0.5 was
    // not centred and 1.0 pushed the item off the bottom — while
    // animateToIndex, which goes through ensureVisible, aligned the box. Two
    // adjacent buttons in the example disagreed on the same argument.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      host(items: List<String>.generate(60, (int i) => 'm$i'), controller: c),
    );
    await tester.pumpAndSettle();

    c.jumpToIndex(30, alignment: 0.5);
    await tester.pumpAndSettle();

    final Rect row = tester.getRect(find.text('m30'));
    final Rect view = tester.getRect(find.byType(AnchoredList));
    // Centred means the row's centre is near the viewport's centre, not its
    // top edge at the centre (which would be 25px lower).
    expect(row.center.dy, closeTo(view.center.dy, 2.0));
  });

  testWidgets('animateToIndex lands where it was asked, not a screen past', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.1.1: alignment was consumed twice — once as the viewport
    // anchor and once by ensureVisible — so the target settled about
    // viewportExtent × alignment beyond its destination.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);

    await tester.pumpWidget(
      host(items: List<String>.generate(60, (int i) => 'm$i'), controller: c),
    );
    await tester.pumpAndSettle();

    // unawaited: animateToIndex awaits endOfFrame, which only arrives once
    // the tester pumps.
    unawaited(
      c.animateToIndex(
        20,
        alignment: 0.5,
        duration: const Duration(milliseconds: 1),
      ),
    );
    await tester.pumpAndSettle();

    final Rect row = tester.getRect(find.text('m20'));
    final Rect view = tester.getRect(find.byType(AnchoredList));
    expect(row.center.dy, closeTo(view.center.dy, 2.0));
  });
}
