// Both defects reported in issue #3 (22 Sep 2026): a list inside a
// TabBarView dragged the tabs sideways when it moved, and animateToIndex
// refused a zero duration instead of behaving like jumpToIndex.
import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget tabbed({
    required AnchoredListController controller,
    required int itemCount,
  }) =>
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              bottom: const TabBar(
                tabs: <Widget>[Tab(text: 'a'), Tab(text: 'b'), Tab(text: 'c')],
              ),
            ),
            body: TabBarView(
              children: <Widget>[
                SizedBox(
                  height: 600,
                  child: AnchoredList.builder(
                    controller: controller,
                    itemCount: itemCount,
                    // Narrower than the page, like a line of transcript: a
                    // box that does not fill the pager's viewport is one the
                    // pager can "reveal" by scrolling sideways.
                    itemBuilder: (BuildContext c, int i) => Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 200,
                        height: 50,
                        child: Text('line $i'),
                      ),
                    ),
                  ),
                ),
                const Text('second tab'),
                const Text('third tab'),
              ],
            ),
          ),
        ),
      );

  /// The horizontal pager behind a [TabBarView].
  ScrollPosition pagerOf(WidgetTester tester) {
    final Iterable<Scrollable> all = tester.widgetList<Scrollable>(
      find.byType(Scrollable),
    );
    final Scrollable pager = all.firstWhere(
      (Scrollable s) => s.axisDirection == AxisDirection.right,
    );
    return (tester.state(find.byWidget(pager)) as ScrollableState).position;
  }

  testWidgets('moving the list leaves the tabs where they were', (
    WidgetTester tester,
  ) async {
    // Scrollable.ensureVisible walks *every* enclosing scrollable and passes
    // each one the same alignment, so the horizontal pager was told to centre
    // the target too and slid toward the next tab. Reported with a screen
    // recording of a transcript follower.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);
    await tester.pumpWidget(tabbed(controller: c, itemCount: 500));
    await tester.pumpAndSettle();

    final ScrollPosition pager = pagerOf(tester);
    final double before = pager.pixels;

    // Never await the scroll before pumping: the future completes only as
    // test time advances, and only pumpAndSettle advances it.
    final Future<void> done = c.animateToIndex(40,
        alignment: 0.5, duration: const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await done;

    expect(pager.pixels, before, reason: 'the tabs moved sideways');
    expect(find.text('line 40'), findsOneWidget);
  });

  testWidgets('a nearby target does not disturb the tabs either', (
    WidgetTester tester,
  ) async {
    // The already-built path, which skips staging and goes straight to the
    // reveal — the case in the video, where the next transcript line is a
    // few rows down.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);
    await tester.pumpWidget(tabbed(controller: c, itemCount: 500));
    await tester.pumpAndSettle();

    final ScrollPosition pager = pagerOf(tester);
    final double before = pager.pixels;

    final Future<void> done = c.animateToIndex(3,
        alignment: 0.5, duration: const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await done;

    expect(pager.pixels, before, reason: 'the tabs moved sideways');
  });

  testWidgets('a zero duration lands like jumpToIndex', (
    WidgetTester tester,
  ) async {
    // The controller asserted duration > zero, so a caller passing
    // Duration.zero got an assertion in debug and, with asserts compiled out,
    // nothing at all.
    final AnchoredListController c = AnchoredListController();
    addTearDown(c.dispose);
    await tester.pumpWidget(tabbed(controller: c, itemCount: 500));
    await tester.pumpAndSettle();

    final Future<void> done = c.animateToIndex(120, duration: Duration.zero);
    await tester.pumpAndSettle();
    await done;

    expect(find.text('line 120'), findsOneWidget);
    expect(c.anchorIndex, 120);
  });

  testWidgets('a zero duration honours alignment, like jumpToIndex', (
    WidgetTester tester,
  ) async {
    final AnchoredListController jump = AnchoredListController();
    final AnchoredListController zero = AnchoredListController();
    addTearDown(jump.dispose);
    addTearDown(zero.dispose);

    await tester.pumpWidget(tabbed(controller: jump, itemCount: 500));
    await tester.pumpAndSettle();
    jump.jumpToIndex(200, alignment: 0.5);
    await tester.pumpAndSettle();
    final Rect jumped = tester.getRect(find.text('line 200'));

    await tester.pumpWidget(tabbed(controller: zero, itemCount: 500));
    await tester.pumpAndSettle();
    final Future<void> done =
        zero.animateToIndex(200, alignment: 0.5, duration: Duration.zero);
    await tester.pumpAndSettle();
    await done;

    expect(tester.getRect(find.text('line 200')).top,
        moreOrLessEquals(jumped.top, epsilon: 1));
  });
}
