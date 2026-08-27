import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

void main() {
  Widget host(Widget child, {Size size = const Size(300, 500)}) => MaterialApp(
    home: Scaffold(
      // Top-left, not centred: the tests assert absolute positions, and a
      // Center would offset every one of them by the surface margin.
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );

  Widget view({
    int itemCount = 40,
    int crossAxisCount = 2,
    double mainAxisSpacing = 0,
    double crossAxisSpacing = 0,
    Axis scrollDirection = Axis.vertical,
    EdgeInsets? padding,
    bool shrinkWrap = false,
    ScrollController? controller,
  }) => MasonryGridView.count(
    crossAxisCount: crossAxisCount,
    mainAxisSpacing: mainAxisSpacing,
    crossAxisSpacing: crossAxisSpacing,
    scrollDirection: scrollDirection,
    padding: padding,
    shrinkWrap: shrinkWrap,
    controller: controller,
    itemCount: itemCount,
    itemBuilder: (BuildContext c, int i) => scrollDirection == Axis.vertical
        ? SizedBox(height: h(i), child: Text('i$i'))
        : SizedBox(width: h(i), child: Text('i$i')),
  );

  group('layout', () {
    testWidgets('columns divide the cross axis, minus the gaps', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(view(crossAxisCount: 3, crossAxisSpacing: 10)),
      );
      await tester.pumpAndSettle();
      // 300 wide, 3 columns, 2 gaps of 10 => (300 - 20) / 3
      for (int i = 0; i < 3; i++) {
        expect(tester.getRect(find.text('i$i')).width, closeTo(280 / 3, 0.01));
      }
      expect(tester.getRect(find.text('i0')).left, 0);
      expect(tester.getRect(find.text('i1')).left, closeTo(280 / 3 + 10, 0.01));
    });

    testWidgets('each item lands in the shortest column', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(view(crossAxisCount: 2)));
      await tester.pumpAndSettle();
      // h(0)=60, h(1)=97 -> column 0 is shorter, so item 2 goes there.
      expect(tester.getRect(find.text('i2')).left, 0);
      expect(tester.getRect(find.text('i2')).top, 60);
    });

    testWidgets('mainAxisSpacing separates items in a column only', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(view(crossAxisCount: 1, mainAxisSpacing: 12)),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')).top, 0);
      expect(tester.getRect(find.text('i1')).top, h(0) + 12);
      expect(tester.getRect(find.text('i2')).top, h(0) + 12 + h(1) + 12);
    });

    testWidgets('works along the horizontal axis', (WidgetTester tester) async {
      await tester.pumpWidget(host(view(scrollDirection: Axis.horizontal)));
      await tester.pumpAndSettle();
      final Rect a = tester.getRect(find.text('i0'));
      final Rect b = tester.getRect(find.text('i1'));
      expect(a.left, b.left, reason: 'first pair starts flush');
      expect(a.top, lessThan(b.top), reason: 'stacked across the cross axis');
    });

    testWidgets('honours padding', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(view(padding: const EdgeInsets.fromLTRB(20, 30, 20, 0))),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')).left, 20);
      expect(tester.getRect(find.text('i0')).top, 30);
    });
  });

  group('laziness', () {
    testWidgets('does not build the whole list up front', (
      WidgetTester tester,
    ) async {
      final Set<int> built = <int>{};
      await tester.pumpWidget(
        host(
          MasonryGridView.count(
            crossAxisCount: 2,
            itemCount: 5000,
            itemBuilder: (BuildContext c, int i) {
              built.add(i);
              return SizedBox(height: h(i), child: Text('i$i'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(built.length, lessThan(60), reason: 'built ${built.length}');
    });
  });

  group('the cache is dropped when its premise changes', () {
    testWidgets('column count change relayouts', (WidgetTester tester) async {
      await tester.pumpWidget(host(view(crossAxisCount: 2)));
      await tester.pumpAndSettle();
      final double twoCols = tester.getRect(find.text('i0')).width;

      await tester.pumpWidget(host(view(crossAxisCount: 4)));
      await tester.pumpAndSettle();
      final double fourCols = tester.getRect(find.text('i0')).width;
      expect(fourCols, lessThan(twoCols));
      expect(fourCols, closeTo(300 / 4, 0.01));
    });

    testWidgets('a narrower viewport relayouts', (WidgetTester tester) async {
      await tester.pumpWidget(host(view(), size: const Size(300, 500)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')).width, closeTo(150, 0.01));

      await tester.pumpWidget(host(view(), size: const Size(200, 500)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')).width, closeTo(100, 0.01));
    });

    testWidgets('growing the item list keeps existing placements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(view(itemCount: 20)));
      await tester.pumpAndSettle();
      final Rect before = tester.getRect(find.text('i3'));

      await tester.pumpWidget(host(view(itemCount: 40)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i3')), before);
    });
  });

  group('edges', () {
    testWidgets('an empty grid builds and does not throw', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(view(itemCount: 0)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MasonryGridView), findsOneWidget);
    });

    testWidgets('a single item sits at the origin', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(host(view(itemCount: 1)));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')).topLeft, Offset.zero);
    });

    testWidgets('fewer items than columns', (WidgetTester tester) async {
      await tester.pumpWidget(host(view(itemCount: 2, crossAxisCount: 5)));
      await tester.pumpAndSettle();
      expect(find.text('i0'), findsOneWidget);
      expect(find.text('i1'), findsOneWidget);
      expect(tester.getRect(find.text('i0')).top, 0);
      expect(tester.getRect(find.text('i1')).top, 0);
    });

    testWidgets('shrinkWrap sizes to the content', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: <Widget>[
              Flexible(child: view(itemCount: 4, shrinkWrap: true)),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('i0'), findsOneWidget);
    });

    testWidgets('explicit children constructor works', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          MasonryGridView(
            crossAxisCount: 2,
            children: List<Widget>.generate(
              12,
              (int i) => SizedBox(height: h(i), child: Text('i$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('i0'), findsOneWidget);
      expect(tester.getRect(find.text('i1')).left, 150);
    });

    testWidgets('rejects impossible configuration', (
      WidgetTester tester,
    ) async {
      expect(
        () => MasonryGridView.count(
          crossAxisCount: 0,
          itemCount: 1,
          itemBuilder: (_, _) => const SizedBox(),
        ),
        throwsAssertionError,
      );
      expect(
        () => MasonryGridView.count(
          crossAxisCount: 2,
          itemCount: -1,
          itemBuilder: (_, _) => const SizedBox(),
        ),
        throwsAssertionError,
      );
    });
  });

  group('scrolling', () {
    testWidgets('reaches the last item', (WidgetTester tester) async {
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(host(view(itemCount: 60, controller: sc)));
      await tester.pumpAndSettle();

      for (int i = 0; i < 60; i++) {
        await tester.drag(find.byType(MasonryGridView), const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text('i59'), findsOneWidget);
      expect(sc.offset, closeTo(sc.position.maxScrollExtent, 1));
    });

    testWidgets('scrolling back shows the first item where it started', (
      WidgetTester tester,
    ) async {
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(host(view(itemCount: 60, controller: sc)));
      await tester.pumpAndSettle();
      final Rect before = tester.getRect(find.text('i0'));

      for (int i = 0; i < 8; i++) {
        await tester.drag(find.byType(MasonryGridView), const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      sc.jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('i0')), before);
    });
  });
}
