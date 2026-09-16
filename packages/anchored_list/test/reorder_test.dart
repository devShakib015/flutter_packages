import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reordering, and in particular the thing that made it worth writing:
/// a drag that crosses the anchor, where the list is two slivers.
void main() {
  const double itemHeight = 50;
  const double viewportHeight = 500; // exactly 10 items
  const Duration pressAndHold = Duration(milliseconds: 600);

  late List<String> items;
  late List<List<int>> reorders;

  setUp(() {
    items = List<String>.generate(40, (int i) => 'Item $i');
    reorders = <List<int>>[];
  });

  /// The move every caller writes, and the one the docs show.
  void apply(int oldIndex, int newIndex) {
    reorders.add(<int>[oldIndex, newIndex]);
    int target = newIndex;
    if (target > oldIndex) target -= 1;
    items.insert(target, items.removeAt(oldIndex));
  }

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 300, height: viewportHeight, child: child),
          ),
        ),
      );

  Widget list({
    AnchoredListController? controller,
    int initialIndex = 0,
    double initialAlignment = 0,
    bool longPressToDrag = true,
    Axis scrollDirection = Axis.vertical,
    ReorderCallback? onReorder,
    void Function(int index)? onReorderStart,
    void Function(int index)? onReorderEnd,
    ReorderItemProxyDecorator? proxyDecorator,
    bool withKeys = true,
    int? itemCount,
  }) =>
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) =>
            AnchoredList.builder(
          controller: controller,
          itemCount: itemCount ?? items.length,
          initialIndex: initialIndex,
          initialAlignment: initialAlignment,
          scrollDirection: scrollDirection,
          longPressToDrag: longPressToDrag,
          proxyDecorator: proxyDecorator,
          onReorderStart: onReorderStart,
          onReorderEnd: onReorderEnd,
          onReorder: (int oldIndex, int newIndex) => setState(
            () => (onReorder ?? apply)(oldIndex, newIndex),
          ),
          itemBuilder: (BuildContext context, int index) => SizedBox(
            key: withKeys ? ValueKey<String>(items[index]) : null,
            height: itemHeight,
            width: scrollDirection == Axis.horizontal ? itemHeight : null,
            child: Text(items[index]),
          ),
        ),
      );

  /// Long-presses [label] and drags it [by] pixels, in steps, so the list
  /// recomputes where it would land the way it does under a real finger.
  Future<void> drag(
    WidgetTester tester,
    String label,
    Offset by, {
    bool release = true,
  }) async {
    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text(label)));
    await tester.pump(pressAndHold);
    const int steps = 10;
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(by / steps.toDouble());
      await tester.pump();
    }
    if (!release) return;
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Where a handful of items are on screen right now.
  Map<String, double> where(WidgetTester tester, List<String> labels) =>
      <String, double>{
        for (final String label in labels)
          label: tester.getTopLeft(find.text(label)).dy,
      };

  group('the claim: a drag crosses the anchor', () {
    testWidgets('an item from above the anchor lands below it', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      // Anchor at 20, half way down, so five items sit above it on screen and
      // five below — the leading sliver and the centre sliver both visible.
      await tester.pumpWidget(
        host(list(controller: c, initialIndex: 20, initialAlignment: 0.5)),
      );
      await tester.pumpAndSettle();
      expect(c.anchorIndex, 20);
      expect(find.text('Item 17'), findsOneWidget);
      expect(find.text('Item 22'), findsOneWidget);

      await drag(tester, 'Item 17', const Offset(0, 200));

      expect(reorders, isNotEmpty, reason: 'the drag never reordered anything');
      expect(
        items.indexOf('Item 17'),
        greaterThan(items.indexOf('Item 20')),
        reason: 'Item 17 should have crossed the anchor and landed below it',
      );
    });

    testWidgets('and the viewport does not slide by a row when it does', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(list(controller: c, initialIndex: 20, initialAlignment: 0.5)),
      );
      await tester.pumpAndSettle();
      // The anchor and its neighbours are the test. A reorder that steps over
      // the anchor changes how many items sit above it, and without the
      // correction every one of these would slide up by a row.
      const List<String> steady = <String>['Item 19', 'Item 20', 'Item 21'];
      final Map<String, double> before = where(tester, steady);

      await drag(tester, 'Item 17', const Offset(0, 200));

      expect(
        c.anchorIndex,
        19,
        reason: 'one item left the region above the anchor',
      );
      expect(where(tester, steady), before);
    });

    testWidgets('an item from below the anchor lands above it', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(list(controller: c, initialIndex: 20, initialAlignment: 0.5)),
      );
      await tester.pumpAndSettle();
      const List<String> steady = <String>['Item 19', 'Item 20', 'Item 21'];
      final Map<String, double> before = where(tester, steady);

      await drag(tester, 'Item 22', const Offset(0, -200));

      expect(
        items.indexOf('Item 22'),
        lessThan(items.indexOf('Item 20')),
        reason: 'Item 22 should have crossed the anchor and landed above it',
      );
      expect(
        c.anchorIndex,
        21,
        reason: 'one item joined the region above the anchor',
      );
      expect(where(tester, steady), before);
    });

    testWidgets(
        'a drag at the edge scrolls past the anchor, into negative '
        'offset', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(list(controller: c, initialIndex: 20, initialAlignment: 0.5)),
      );
      await tester.pumpAndSettle();
      expect(c.scrollController.offset, 0);

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.text('Item 22')));
      await tester.pump(pressAndHold);
      await gesture.moveBy(const Offset(0, -380));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Offset zero is the anchor, so scrolling above it is negative. That
      // the auto-scroller goes there at all is the point: the two slivers are
      // one scroll space, and a drag crosses the anchor without noticing it.
      expect(c.scrollController.offset, lessThan(0));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('items on both sides of the anchor open the gap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(list(initialIndex: 20, initialAlignment: 0.5)),
      );
      await tester.pumpAndSettle();
      final double above = tester.getTopLeft(find.text('Item 18')).dy;
      final double below = tester.getTopLeft(find.text('Item 21')).dy;

      // Hold the drag open rather than releasing it.
      await drag(tester, 'Item 17', const Offset(0, 200), release: false);
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Item 18')).dy,
        lessThan(above),
        reason: 'an item above the anchor should slide up into the gap',
      );
      expect(
        tester.getTopLeft(find.text('Item 21')).dy,
        lessThan(below),
        reason: 'an item below the anchor should slide up into the gap too',
      );
    });
  });

  group('the ordinary case', () {
    testWidgets('a long press and a drag moves an item down', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list()));
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150));

      expect(items.indexOf('Item 2'), greaterThan(items.indexOf('Item 4')));
      expect(items.first, 'Item 0');
      expect(items.length, 40, reason: 'nothing should be lost or duplicated');
    });

    testWidgets('and back up again', (WidgetTester tester) async {
      await tester.pumpWidget(host(list()));
      await tester.pump();

      await drag(tester, 'Item 5', const Offset(0, -150));

      expect(items.indexOf('Item 5'), lessThan(items.indexOf('Item 3')));
    });

    testWidgets('an item dropped at the very start lands at index 0', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list()));
      await tester.pumpAndSettle();

      await drag(tester, 'Item 4', const Offset(0, -250));

      expect(items.first, 'Item 4');
      expect(items[1], 'Item 0');
    });

    testWidgets('a horizontal list reorders along its own axis', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list(scrollDirection: Axis.horizontal)));
      await tester.pump();

      await drag(tester, 'Item 1', const Offset(150, 0));

      expect(items.indexOf('Item 1'), greaterThan(items.indexOf('Item 3')));
    });

    testWidgets('a separated list drags the item with its separator', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                AnchoredList.separated(
              itemCount: items.length,
              onReorder: (int oldIndex, int newIndex) =>
                  setState(() => apply(oldIndex, newIndex)),
              itemBuilder: (BuildContext context, int index) => SizedBox(
                key: ValueKey<String>(items[index]),
                height: itemHeight,
                child: Text(items[index]),
              ),
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 10),
            ),
          ),
        ),
      );
      await tester.pump();

      await drag(tester, 'Item 1', const Offset(0, 130));

      expect(items.indexOf('Item 1'), greaterThan(items.indexOf('Item 2')));
    });
  });

  group('how a drag starts', () {
    testWidgets('longPressToDrag false ignores a press on the item', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list(longPressToDrag: false)));
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150));

      expect(reorders, isEmpty);
      expect(items.indexOf('Item 2'), 2);
    });

    testWidgets('a handle drags immediately, without the long press', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) =>
                AnchoredList.builder(
              itemCount: items.length,
              longPressToDrag: false,
              onReorder: (int oldIndex, int newIndex) =>
                  setState(() => apply(oldIndex, newIndex)),
              itemBuilder: (BuildContext context, int index) => Row(
                key: ValueKey<String>(items[index]),
                children: <Widget>[
                  Expanded(
                    child:
                        SizedBox(height: itemHeight, child: Text(items[index])),
                  ),
                  AnchoredListDragStartListener(
                    index: index,
                    child: SizedBox(
                      height: itemHeight,
                      width: 40,
                      child: Text('grip ${items[index]}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(find.text('grip Item 2')));
      await tester.pump(kLongPressTimeout ~/ 4);
      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 15));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(items.indexOf('Item 2'), greaterThan(items.indexOf('Item 3')));
    });
  });

  group('the callbacks', () {
    testWidgets('start and end bracket the drag', (WidgetTester tester) async {
      final List<String> log = <String>[];
      await tester.pumpWidget(
        host(
          list(
            onReorderStart: (int i) => log.add('start $i'),
            onReorderEnd: (int i) => log.add('end $i'),
          ),
        ),
      );
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150));

      expect(log.first, 'start 2');
      expect(log.length, 2);
      expect(log.last, startsWith('end '));
    });

    testWidgets('newIndex follows the ReorderableListView convention', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list()));
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150));

      final List<int> move = reorders.single;
      expect(move[0], 2);
      expect(
        move[1],
        greaterThan(move[0] + 1),
        reason: 'a move down counts with the dragged item still in place',
      );
    });

    testWidgets('the proxy decorator wraps the item in the air', (
      WidgetTester tester,
    ) async {
      var decorated = 0;
      await tester.pumpWidget(
        host(
          list(
            proxyDecorator: (Widget child, int index, Animation<double> a) {
              decorated++;
              return ColoredBox(color: const Color(0xFF00FF00), child: child);
            },
          ),
        ),
      );
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 100), release: false);
      expect(decorated, greaterThan(0));
    });
  });

  group('edges', () {
    testWidgets('a list that changes length mid-drag cancels it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list(itemCount: 40)));
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150), release: false);
      await tester.pumpWidget(host(list(itemCount: 39)));
      await tester.pumpAndSettle();

      expect(reorders, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an item without a key is refused, loudly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(list(withKeys: false)));
      await tester.pump();
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('a list with no onReorder does not drag at all', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          AnchoredList.builder(
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) => SizedBox(
              key: ValueKey<String>(items[index]),
              height: itemHeight,
              child: Text(items[index]),
            ),
          ),
        ),
      );
      await tester.pump();

      await drag(tester, 'Item 2', const Offset(0, 150));

      expect(items.indexOf('Item 2'), 2);
      expect(reorders, isEmpty);
    });

    testWidgets('dragging still works after a jump', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      await tester.pump();

      c.jumpToIndex(30);
      await tester.pumpAndSettle();
      expect(find.text('Item 31'), findsOneWidget);

      await drag(tester, 'Item 31', const Offset(0, 150));

      expect(items.indexOf('Item 31'), greaterThan(items.indexOf('Item 33')));
    });
  });
}
