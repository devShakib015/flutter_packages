import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const double itemHeight = 50;
  const double viewportHeight = 500; // exactly 10 items

  late List<int> built;

  Widget host(Widget child, {double height = viewportHeight}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 300, height: height, child: child),
      ),
    ),
  );

  Widget list({
    required AnchoredListController controller,
    int itemCount = 1000000,
    int initialIndex = 0,
    double initialAlignment = 0,
  }) => AnchoredList.builder(
    controller: controller,
    itemCount: itemCount,
    initialIndex: initialIndex,
    initialAlignment: initialAlignment,
    itemBuilder: (BuildContext context, int index) {
      built.add(index);
      return SizedBox(height: itemHeight, child: Text('Item $index'));
    },
  );

  setUp(() => built = <int>[]);

  group('the claim: jumping is constant time', () {
    testWidgets('starting deep in a huge list builds only a screenful', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);

      await tester.pumpWidget(host(list(controller: c, initialIndex: 500000)));
      await tester.pump();

      expect(find.text('Item 500000'), findsOneWidget);
      // The whole point: nothing before the anchor is built, so this is a
      // screenful and a cache margin — not half a million widgets.
      expect(
        built.length,
        lessThan(60),
        reason: 'built ${built.length} items to show one',
      );
      expect(
        built.every((int i) => i >= 499000),
        isTrue,
        reason: 'should not have built items far above the anchor',
      );
    });

    testWidgets('jumping 300k items costs the same as jumping 3', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      await tester.pump();

      built.clear();
      c.jumpToIndex(3);
      await tester.pumpAndSettle();
      final int near = built.length;

      built.clear();
      c.jumpToIndex(300000);
      await tester.pumpAndSettle();
      final int far = built.length;

      expect(find.text('Item 300000'), findsOneWidget);
      expect(
        far,
        lessThan(near * 3 + 30),
        reason: 'near cost $near, far cost $far — should be comparable',
      );
    });
  });

  group('anchoring', () {
    testWidgets('shows the anchor at the leading edge by default', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 100)));
      await tester.pump();

      final double top = tester.getTopLeft(find.text('Item 100')).dy;
      final double viewportTop = tester
          .getTopLeft(find.byType(AnchoredList))
          .dy;
      expect(top, moreOrLessEquals(viewportTop, epsilon: 1));
    });

    testWidgets('alignment 0.5 centres the anchor', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(list(controller: c, initialIndex: 100, initialAlignment: 0.5)),
      );
      await tester.pump();

      final Rect item = tester.getRect(find.text('Item 100'));
      final Rect viewport = tester.getRect(find.byType(AnchoredList));
      expect(
        item.top - viewport.top,
        moreOrLessEquals(viewportHeight / 2, epsilon: 1),
      );
    });

    testWidgets('items before the anchor exist and are reachable', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 500)));
      await tester.pump();

      // Scrolling back moves into negative offset, which is the whole trick.
      await tester.drag(find.byType(AnchoredList), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.text('Item 494'), findsOneWidget);
    });

    testWidgets('anchorIndex reports where the list is anchored', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 7)));
      await tester.pump();
      expect(c.anchorIndex, 7);

      c.jumpToIndex(42);
      await tester.pumpAndSettle();
      expect(c.anchorIndex, 42);
    });
  });

  group('the trade this technique makes', () {
    testWidgets('shrinkWrap is absent, because centre forbids it', (
      WidgetTester tester,
    ) async {
      // Flutter asserts `!shrinkWrap || center == null`, so a centre-anchored
      // viewport can never size to its content. The parameter is not offered
      // rather than offered and broken — and the archived package, which uses
      // two plain ListViews, genuinely does support it. This is the one place
      // that design wins.
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, itemCount: 3)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Item 0'), findsOneWidget);
      // Fills the space it is given rather than hugging three items.
      expect(
        tester.getSize(find.byType(AnchoredList)).height,
        moreOrLessEquals(viewportHeight, epsilon: 1),
      );
    });
  });

  group('item positions', () {
    testWidgets('reports what is on screen, as viewport fractions', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 200)));
      await tester.pumpAndSettle();

      final List<ItemPosition> visible = c.itemPositions.value
          .where((ItemPosition p) => p.isVisible)
          .toList();

      expect(visible, isNotEmpty);
      expect(visible.first.index, 200);
      // 500px viewport, 50px items: exactly ten fully visible.
      expect(visible.where((ItemPosition p) => p.isFullyVisible).length, 10);
      expect(visible.first.leadingEdge, moreOrLessEquals(0, epsilon: 0.01));
      expect(visible.first.extent, moreOrLessEquals(0.1, epsilon: 0.01));
    });

    testWidgets('updates as the list scrolls', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      await tester.pumpAndSettle();
      expect(c.itemPositions.value.first.index, 0);

      await tester.drag(find.byType(AnchoredList), const Offset(0, -250));
      await tester.pumpAndSettle();

      final int firstVisible = c.itemPositions.value
          .firstWhere((ItemPosition p) => p.isVisible)
          .index;
      expect(firstVisible, 5, reason: 'scrolled 250px over 50px items');
    });
  });

  group('animateToIndex', () {
    testWidgets('reaches a nearby target smoothly', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      await tester.pumpAndSettle();

      unawaited(c.animateToIndex(8));
      await tester.pumpAndSettle();
      expect(find.text('Item 8'), findsOneWidget);
    });

    testWidgets('reaches a far target too', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      await tester.pumpAndSettle();

      unawaited(c.animateToIndex(75000));
      await tester.pumpAndSettle();
      expect(find.text('Item 75000'), findsOneWidget);
    });
  });

  group('edges', () {
    testWidgets('an empty list builds nothing and does not throw', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, itemCount: 0)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(built, isEmpty);

      c.jumpToIndex(5);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('an out-of-range index is clamped, not crashed', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, itemCount: 10)));
      await tester.pump();

      c.jumpToIndex(9999);
      await tester.pumpAndSettle();
      expect(c.anchorIndex, 9);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unattached controller says so clearly', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      expect(c.isAttached, isFalse);
      expect(() => c.jumpToIndex(1), throwsStateError);
    });

    testWidgets('rejects impossible configuration', (
      WidgetTester tester,
    ) async {
      expect(
        () => AnchoredList.builder(
          itemCount: -1,
          itemBuilder: (_, _) => const SizedBox(),
        ),
        throwsAssertionError,
      );
      expect(
        () => AnchoredList.builder(
          itemCount: 1,
          initialAlignment: 2,
          itemBuilder: (_, _) => const SizedBox(),
        ),
        throwsAssertionError,
      );
    });
  });
}

void unawaited(Future<void> f) {}
