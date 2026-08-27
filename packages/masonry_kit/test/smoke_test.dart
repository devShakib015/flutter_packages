import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart';

double h(int i) => 60.0 + (i * 37) % 90;

void main() {
  testWidgets('renders children in columns', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MasonryGridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            itemCount: 30,
            itemBuilder: (BuildContext c, int i) =>
                SizedBox(height: h(i), child: Text('item $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('item 0'), findsOneWidget);
    expect(find.text('item 1'), findsOneWidget);

    final Rect a = tester.getRect(find.text('item 0'));
    final Rect b = tester.getRect(find.text('item 1'));
    // ignore: avoid_print
    print('  item0 $a');
    // ignore: avoid_print
    print('  item1 $b');
    // Two columns: the first two items sit side by side, both at the top.
    expect(a.top, b.top, reason: 'first row should be flush');
    expect(a.left, lessThan(b.left), reason: 'item 1 is in the next column');
    expect(a.width, closeTo(b.width, 0.01));
  });
}
