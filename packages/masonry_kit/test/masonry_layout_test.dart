import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/src/masonry_layout.dart';

void main() {
  MasonryLayout make({int columns = 3, double spacing = 0}) =>
      MasonryLayout(crossAxisCount: columns, mainAxisSpacing: spacing);

  group('placement', () {
    test('the first row fills every column flush with the start', () {
      final MasonryLayout l = make(spacing: 8);
      for (int i = 0; i < 3; i++) {
        l.append(100);
      }
      for (int i = 0; i < 3; i++) {
        expect(l.slotOf(i).column, i);
        expect(l.slotOf(i).offset, 0, reason: 'no item above it to space from');
      }
    });

    test('each item goes to the shortest column', () {
      final MasonryLayout l = make();
      l.append(100); // col 0
      l.append(50); // col 1
      l.append(80); // col 2
      // Column 1 is shortest at 50.
      expect(l.append(10).column, 1);
      // Now col 1 is 60, col 2 is 80, col 0 is 100 — col 1 again.
      expect(l.append(10).column, 1);
      // col 1 = 70, still shortest.
      expect(l.append(40).column, 1);
      // col 1 = 110, col 2 = 80 is now shortest.
      expect(l.append(10).column, 2);
    });

    test('equal columns fill left to right, so runs are reproducible', () {
      final MasonryLayout a = make();
      final MasonryLayout b = make();
      for (int i = 0; i < 12; i++) {
        a.append(50);
        b.append(50);
      }
      for (int i = 0; i < 12; i++) {
        expect(a.slotOf(i).column, b.slotOf(i).column);
        expect(a.slotOf(i).offset, b.slotOf(i).offset);
      }
    });

    test('spacing goes between items in a column, never before the first', () {
      final MasonryLayout l = make(columns: 1, spacing: 10);
      l.append(100);
      expect(l.slotOf(0).offset, 0);
      l.append(100);
      expect(l.slotOf(1).offset, 110);
      l.append(100);
      expect(l.slotOf(2).offset, 220);
      expect(l.extent, 320);
    });
  });

  group('the promise: a placement is never revised', () {
    test('appending never moves an item already placed', () {
      final MasonryLayout l = make(spacing: 4);
      final List<MasonrySlot> seen = <MasonrySlot>[];
      for (int i = 0; i < 200; i++) {
        seen.add(l.append(30.0 + (i * 17) % 120));
      }
      for (int i = 0; i < 200; i++) {
        expect(l.slotOf(i).column, seen[i].column);
        expect(l.slotOf(i).offset, seen[i].offset);
        expect(l.slotOf(i).extent, seen[i].extent);
      }
    });

    test('extent only ever grows', () {
      final MasonryLayout l = make(spacing: 6);
      double previous = 0;
      for (int i = 0; i < 300; i++) {
        l.append(20.0 + (i * 29) % 150);
        expect(l.extent, greaterThanOrEqualTo(previous));
        previous = l.extent;
      }
    });

    test('the shortest column only ever grows too', () {
      final MasonryLayout l = make(columns: 4);
      double previous = 0;
      for (int i = 0; i < 300; i++) {
        l.append(20.0 + (i * 41) % 130);
        expect(l.shortestColumnExtent, greaterThanOrEqualTo(previous));
        previous = l.shortestColumnExtent;
      }
    });
  });

  group('window queries', () {
    test('items overlapping a window are a contiguous index range', () {
      final MasonryLayout l = make(columns: 3, spacing: 5);
      for (int i = 0; i < 400; i++) {
        l.append(25.0 + (i * 23) % 140);
      }
      for (double start = 0; start < l.extent - 300; start += 137) {
        final double end = start + 300;
        final int first = l.firstIndexAfter(start);
        final int last = l.lastIndexBefore(end);
        // Everything the window touches must fall inside [first, last]:
        // if that held only for some, a contiguous child list would be wrong.
        for (int i = 0; i < l.count; i++) {
          final MasonrySlot s = l.slotOf(i);
          if (s.end > start && s.offset < end) {
            expect(
              i,
              inInclusiveRange(first, last),
              reason:
                  'item $i overlaps $start..$end but sits outside '
                  'the range $first..$last',
            );
          }
        }
      }
    });

    test('an empty layout answers without throwing', () {
      final MasonryLayout l = make();
      expect(l.isEmpty, isTrue);
      expect(l.extent, 0);
      expect(l.shortestColumnExtent, 0);
      expect(l.firstIndexAfter(0), 0);
      expect(l.lastIndexBefore(1000), -1);
    });
  });

  group('reset', () {
    test('clears placements and column heights', () {
      final MasonryLayout l = make();
      for (int i = 0; i < 20; i++) {
        l.append(50);
      }
      l.reset();
      expect(l.count, 0);
      expect(l.extent, 0);
      expect(l.append(10).offset, 0);
    });
  });

  group('rejects impossible configuration', () {
    test('zero columns', () {
      expect(
        () => MasonryLayout(crossAxisCount: 0, mainAxisSpacing: 0),
        throwsAssertionError,
      );
    });
    test('negative spacing', () {
      expect(
        () => MasonryLayout(crossAxisCount: 2, mainAxisSpacing: -1),
        throwsAssertionError,
      );
    });
  });
}
