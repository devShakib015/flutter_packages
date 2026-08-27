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

  group('items arriving above the anchor', () {
    // Issues #145, #311 and #373 on the archived tracker all ask for this.
    Widget growable({
      required AnchoredListController controller,
      required List<String> Function() read,
      required void Function(StateSetter) capture,
      int initialIndex = 200,
    }) => StatefulBuilder(
      builder: (BuildContext context, StateSetter setOuter) {
        capture(setOuter);
        return AnchoredList.builder(
          controller: controller,
          initialIndex: initialIndex,
          itemCount: read().length,
          itemBuilder: (BuildContext context, int index) =>
              SizedBox(height: itemHeight, child: Text(read()[index])),
        );
      },
    );

    testWidgets('prepending without saying so drifts the view', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      List<String> data = List<String>.generate(500, (int i) => 'row-$i');
      late StateSetter setOuter;

      await tester.pumpWidget(
        host(
          growable(
            controller: c,
            read: () => data,
            capture: (StateSetter s) => setOuter = s,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Offset anchorSpot = tester.getTopLeft(find.text('row-200'));

      setOuter(() {
        data = <String>[
          ...List<String>.generate(10, (int i) => 'older-$i'),
          ...data,
        ];
      });
      await tester.pumpAndSettle();

      // The anchor is still index 200, which is now a different row.
      expect(tester.getTopLeft(find.text('row-190')), anchorSpot);
    });

    testWidgets('itemsInsertedAbove holds the same pixels', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      List<String> data = List<String>.generate(500, (int i) => 'row-$i');
      late StateSetter setOuter;

      await tester.pumpWidget(
        host(
          growable(
            controller: c,
            read: () => data,
            capture: (StateSetter s) => setOuter = s,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Offset before = tester.getTopLeft(find.text('row-200'));

      setOuter(() {
        data = <String>[
          ...List<String>.generate(10, (int i) => 'older-$i'),
          ...data,
        ];
      });
      c.itemsInsertedAbove(10);
      await tester.pumpAndSettle();

      expect(c.anchorIndex, 210);
      expect(tester.getTopLeft(find.text('row-200')), before);
    });

    testWidgets('holds mid-item, not just on item boundaries', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      List<String> data = List<String>.generate(500, (int i) => 'row-$i');
      late StateSetter setOuter;

      await tester.pumpWidget(
        host(
          growable(
            controller: c,
            read: () => data,
            capture: (StateSetter s) => setOuter = s,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Park the viewport 23px into the anchored row, so a fix that only
      // works on whole items would show up.
      c.scrollController.jumpTo(23);
      await tester.pumpAndSettle();
      final Offset before = tester.getTopLeft(find.text('row-200'));

      setOuter(() {
        data = <String>[
          ...List<String>.generate(7, (int i) => 'older-$i'),
          ...data,
        ];
      });
      c.itemsInsertedAbove(7);
      await tester.pumpAndSettle();

      expect(c.scrollController.offset, 23);
      expect(tester.getTopLeft(find.text('row-200')), before);
    });

    testWidgets('itemsRemovedAbove is the inverse', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      List<String> data = List<String>.generate(500, (int i) => 'row-$i');
      late StateSetter setOuter;

      await tester.pumpWidget(
        host(
          growable(
            controller: c,
            read: () => data,
            capture: (StateSetter s) => setOuter = s,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Offset before = tester.getTopLeft(find.text('row-200'));

      setOuter(() => data = data.sublist(5));
      c.itemsRemovedAbove(5);
      await tester.pumpAndSettle();

      expect(c.anchorIndex, 195);
      expect(tester.getTopLeft(find.text('row-200')), before);
    });

    testWidgets('a negative count is rejected', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c)));
      expect(() => c.itemsInsertedAbove(-1), throwsAssertionError);
      expect(() => c.itemsRemovedAbove(-1), throwsAssertionError);
    });
  });

  group('scroll controller', () {
    testWidgets('exposes the one it made', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 100)));
      await tester.pumpAndSettle();
      expect(c.scrollController.hasClients, isTrue);
    });

    testWidgets('uses one supplied by the caller', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      final ScrollController mine = ScrollController();
      addTearDown(c.dispose);
      addTearDown(mine.dispose);

      await tester.pumpWidget(
        host(
          AnchoredList.builder(
            controller: c,
            scrollController: mine,
            itemCount: 1000,
            initialIndex: 500,
            itemBuilder: (BuildContext context, int index) =>
                SizedBox(height: itemHeight, child: Text('Item $index')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(identical(c.scrollController, mine), isTrue);
      expect(mine.hasClients, isTrue);
    });

    testWidgets('offsets are measured from the anchor', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(list(controller: c, initialIndex: 100)));
      await tester.pumpAndSettle();

      expect(c.scrollController.offset, 0);
      // Everything above the anchor lives at negative offset.
      expect(c.scrollController.position.minScrollExtent, lessThan(0));

      c.scrollController.jumpTo(-itemHeight);
      await tester.pumpAndSettle();
      expect(find.text('Item 99'), findsOneWidget);
    });

    testWidgets('a Scrollbar can attach to it', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      final ScrollController mine = ScrollController();
      addTearDown(c.dispose);
      addTearDown(mine.dispose);

      await tester.pumpWidget(
        host(
          Scrollbar(
            controller: mine,
            thumbVisibility: true,
            child: AnchoredList.builder(
              controller: c,
              scrollController: mine,
              itemCount: 1000,
              initialIndex: 400,
              itemBuilder: (BuildContext context, int index) =>
                  SizedBox(height: itemHeight, child: Text('Item $index')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollbar), findsOneWidget);
    });

    testWidgets('does not dispose a controller it does not own', (
      WidgetTester tester,
    ) async {
      final ScrollController mine = ScrollController();
      await tester.pumpWidget(
        host(
          AnchoredList.builder(
            scrollController: mine,
            itemCount: 100,
            itemBuilder: (BuildContext context, int index) =>
                SizedBox(height: itemHeight, child: Text('Item $index')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(const SizedBox()));
      // Would throw if the list had already disposed it.
      expect(mine.dispose, returnsNormally);
    });
  });

  group('separated', () {
    Widget separated({
      int initialIndex = 0,
      int itemCount = 5,
      AnchoredListController? controller,
    }) => AnchoredList.separated(
      controller: controller,
      itemCount: itemCount,
      initialIndex: initialIndex,
      itemBuilder: (BuildContext context, int index) =>
          SizedBox(height: itemHeight, child: Text('Item $index')),
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 10, child: Text('sep')),
    );

    testWidgets('separates items but not after the last one', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(separated()));
      await tester.pumpAndSettle();
      expect(find.text('Item 4'), findsOneWidget);
      expect(find.text('sep'), findsNWidgets(4));
    });

    testWidgets('separates on both sides of the anchor', (
      WidgetTester tester,
    ) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(separated(initialIndex: 2, controller: c)));
      await tester.pumpAndSettle();

      // With alignment 0 the anchor sits at the leading edge, so items before
      // it begin off-screen above. Scroll back to reveal them.
      final ScrollController scroll = c.scrollController;
      scroll.jumpTo(scroll.position.minScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Item 4'), findsOneWidget);
      expect(find.text('sep'), findsNWidgets(4));
    });

    testWidgets('still jumps in constant time', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(
          AnchoredList.separated(
            controller: c,
            itemCount: 1000000,
            itemBuilder: (BuildContext context, int index) {
              built.add(index);
              return SizedBox(height: itemHeight, child: Text('Item $index'));
            },
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(height: 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      built.clear();
      c.jumpToIndex(750000);
      await tester.pumpAndSettle();
      expect(built.length, lessThan(60));
      expect(find.text('Item 750000'), findsOneWidget);
    });
  });

  group('explicit children', () {
    testWidgets('renders them and still jumps', (WidgetTester tester) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(
          AnchoredList(
            controller: c,
            children: List<Widget>.generate(
              40,
              (int i) => SizedBox(height: itemHeight, child: Text('Item $i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);

      c.jumpToIndex(30);
      await tester.pumpAndSettle();
      expect(find.text('Item 30'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('items above the anchor report their real index', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);

      await tester.pumpWidget(host(list(controller: c, initialIndex: 100)));
      await tester.pumpAndSettle();
      c.scrollController.jumpTo(-2 * itemHeight);
      await tester.pumpAndSettle();

      // The leading sliver counts backwards from the anchor; without a
      // translation these would be announced in reverse.
      expect(tester.getSemantics(find.text('Item 98')).indexInParent, 98);
      expect(tester.getSemantics(find.text('Item 99')).indexInParent, 99);
      expect(tester.getSemantics(find.text('Item 100')).indexInParent, 100);
      handle.dispose();
    });
  });
  group('findChildIndexCallback', () {
    // Insert above a visible item, so everything below it shifts one slot.
    Future<Map<String, int>> insertAbove(
      WidgetTester tester, {
      required bool withCallback,
    }) async {
      final AnchoredListController c = AnchoredListController();
      addTearDown(c.dispose);
      final List<String> data = List<String>.generate(20, (int i) => 'id-$i');
      final Map<String, int> creations = <String, int>{};
      late StateSetter setOuter;

      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (BuildContext context, StateSetter set) {
              setOuter = set;
              return AnchoredList.builder(
                controller: c,
                itemCount: data.length,
                findChildIndexCallback: withCallback
                    ? (Key key) {
                        final int i = data.indexOf(
                          (key as ValueKey<String>).value,
                        );
                        return i == -1 ? null : i;
                      }
                    : null,
                itemBuilder: (BuildContext context, int index) => _Counted(
                  key: ValueKey<String>(data[index]),
                  id: data[index],
                  creations: creations,
                  height: itemHeight,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(creations['id-5'], 1);

      setOuter(() => data.insert(2, 'fresh'));
      await tester.pumpAndSettle();
      return creations;
    }

    testWidgets('without it, an insertion rebuilds everything below', (
      WidgetTester tester,
    ) async {
      final Map<String, int> creations = await insertAbove(
        tester,
        withCallback: false,
      );
      expect(creations['id-5'], 2);
    });

    testWidgets('with it, items below keep their state', (
      WidgetTester tester,
    ) async {
      final Map<String, int> creations = await insertAbove(
        tester,
        withCallback: true,
      );
      expect(creations['id-5'], 1);
    });
  });
}

void unawaited(Future<void> f) {}

/// Records how many times each id was built from scratch, so a test can tell
/// element reuse from element replacement.
class _Counted extends StatefulWidget {
  const _Counted({
    super.key,
    required this.id,
    required this.creations,
    required this.height,
  });

  final String id;
  final Map<String, int> creations;
  final double height;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.creations[widget.id] = (widget.creations[widget.id] ?? 0) + 1;
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: widget.height, child: Text(widget.id));
}
