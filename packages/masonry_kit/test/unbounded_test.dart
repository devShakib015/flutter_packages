// A feed with no declared end. Before 0.4.0 this threw during layout:
// performLayout read childManager.childCount unconditionally, which for a
// delegate with no childCount makes Flutter hunt for the last child and, on a
// genuinely unbounded builder, fail.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

void main() {
  group('a feed with no declared end', () {
    testWidgets('scrolls without ever asking how long it is', (
      WidgetTester tester,
    ) async {
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: sc,
              slivers: <Widget>[
                SliverMasonryGrid.builder(
                  crossAxisCount: 2,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: h(i), child: Text('i$i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('i0'), findsOneWidget);

      for (int i = 0; i < 25; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(sc.offset, greaterThan(2000), reason: 'kept going');
      // Nothing has told it where the end is, so it must not pretend to know.
      expect(sc.position.maxScrollExtent, double.infinity);
    });

    testWidgets('stops where the builder stops', (WidgetTester tester) async {
      // The end announces itself by the builder returning null — the same
      // contract ListView.builder has.
      const int realEnd = 30;
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: sc,
              slivers: <Widget>[
                SliverMasonryGrid.builder(
                  crossAxisCount: 2,
                  itemBuilder: (BuildContext c, int i) => i >= realEnd
                      ? null
                      : SizedBox(height: h(i), child: Text('i$i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (int i = 0; i < 20; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
      expect(find.text('i$realEnd'), findsNothing);
      // Once the end is known the extent must become finite, or the scrollbar
      // never settles and the list scrolls into empty space forever.
      expect(sc.position.maxScrollExtent.isFinite, isTrue);
      expect(sc.offset, lessThanOrEqualTo(sc.position.maxScrollExtent + 1));
    });

    testWidgets(
        'a known itemCount still estimates rather than claiming '
        'infinity', (WidgetTester tester) async {
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: sc,
              slivers: <Widget>[
                SliverMasonryGrid.builder(
                  crossAxisCount: 2,
                  itemCount: 200,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: h(i), child: Text('i$i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(sc.position.maxScrollExtent.isFinite, isTrue);
      expect(sc.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('MasonryGridView.builder does the same', (
      WidgetTester tester,
    ) async {
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MasonryGridView.builder(
              controller: sc,
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              itemBuilder: (BuildContext c, int i) =>
                  SizedBox(height: h(i), child: Text('i$i')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('i0'), findsOneWidget);

      for (int i = 0; i < 15; i++) {
        await tester.drag(find.byType(MasonryGridView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(sc.offset, greaterThan(1000));
    });

    testWidgets(
        'two unbounded grids in one CustomScrollView still do not '
        'jump backwards', (WidgetTester tester) async {
      // The whole reason this package exists, now in the unbounded case.
      final ScrollController sc = ScrollController();
      addTearDown(sc.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: sc,
              slivers: <Widget>[
                SliverMasonryGrid.builder(
                  crossAxisCount: 2,
                  itemCount: 60,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: h(i), child: Text('a$i')),
                ),
                SliverMasonryGrid.builder(
                  crossAxisCount: 2,
                  itemBuilder: (BuildContext c, int i) =>
                      SizedBox(height: h(i + 7), child: Text('b$i')),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      double previous = sc.offset;
      int jumps = 0;
      for (int i = 0; i < 30; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
        await tester.pumpAndSettle();
        if (sc.offset < previous - 1) jumps++;
        previous = sc.offset;
      }
      expect(jumps, 0);
      expect(tester.takeException(), isNull);
    });
  });
}
