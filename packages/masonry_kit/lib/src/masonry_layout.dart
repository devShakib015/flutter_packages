import 'dart:math' as math;

/// Where one item sits: which column, and how far down that column.
class MasonrySlot {
  /// Creates a slot at [offset] in [column], [extent] long.
  const MasonrySlot({
    required this.column,
    required this.offset,
    required this.extent,
  });

  /// Zero-based column index.
  final int column;

  /// Distance from the start of the grid to the item's leading edge.
  final double offset;

  /// The item's measured extent along the scroll axis.
  final double extent;

  /// Distance from the start of the grid to the item's trailing edge.
  double get end => offset + extent;

  @override
  String toString() => 'MasonrySlot(col $column, $offset..$end)';
}

/// Assigns items to columns, shortest column first, and remembers the result.
///
/// The remembering is the whole point. Masonry is sequential — you cannot know
/// where item 400 goes without the measured heights of the 399 before it — so
/// the usual approach is to estimate and then correct, and every correction is
/// a chance for the viewport to move under the reader.
///
/// This never revises. Once [append] has placed an item, its column and offset
/// are final, and [slotOf] will return the same answer for the life of the
/// layout. Anything the viewport has already shown therefore cannot move.
/// Changing the item list or the cross-axis geometry invalidates the premise,
/// so those call [reset] and start again from index 0.
class MasonryLayout {
  /// Creates an empty layout for [crossAxisCount] columns.
  MasonryLayout({required this.crossAxisCount, required this.mainAxisSpacing})
      : assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
        assert(mainAxisSpacing >= 0, 'mainAxisSpacing cannot be negative'),
        _columnEnd = List<double>.filled(crossAxisCount, 0);

  /// How many columns items are distributed across.
  final int crossAxisCount;

  /// Gap inserted between two items in the same column.
  final double mainAxisSpacing;

  final List<MasonrySlot> _slots = <MasonrySlot>[];

  /// Trailing edge of the last item in each column, before spacing.
  final List<double> _columnEnd;

  /// True while no item has been placed.
  bool get isEmpty => _slots.isEmpty;

  /// How many items have been measured and placed.
  int get count => _slots.length;

  /// Total extent of the placed items — the height of the tallest column.
  double get extent => _slots.isEmpty ? 0 : _columnEnd.reduce(math.max);

  /// Extent of the shortest column.
  ///
  /// Nothing placed later can begin before this, which is what makes the
  /// visible items a contiguous range of indices even though their offsets
  /// are not monotonic.
  double get shortestColumnExtent =>
      _slots.isEmpty ? 0 : _columnEnd.reduce(math.min);

  /// The slot for [index], which must already have been placed.
  MasonrySlot slotOf(int index) => _slots[index];

  /// Places the next item, whose measured size along the scroll axis is
  /// [extent], in whichever column is currently shortest.
  MasonrySlot append(double extent) {
    int column = 0;
    for (int i = 1; i < crossAxisCount; i++) {
      // Strictly less, so equal columns fill left to right and the result is
      // reproducible for the same input.
      if (_columnEnd[i] < _columnEnd[column]) column = i;
    }
    final double offset = _slots.length < crossAxisCount
        ? 0 // The first row starts flush; there is nothing above it to space.
        : _columnEnd[column] + mainAxisSpacing;
    final MasonrySlot slot = MasonrySlot(
      column: column,
      offset: offset,
      extent: extent,
    );
    _slots.add(slot);
    _columnEnd[column] = offset + extent;
    return slot;
  }

  /// Index of the first placed item whose trailing edge is past [offset].
  ///
  /// Returns [count] when every placed item ends before it.
  int firstIndexAfter(double offset) {
    for (int i = 0; i < _slots.length; i++) {
      if (_slots[i].end > offset) return i;
    }
    return _slots.length;
  }

  /// Index of the last placed item that begins before [offset], or -1.
  int lastIndexBefore(double offset) {
    for (int i = _slots.length - 1; i >= 0; i--) {
      if (_slots[i].offset < offset) return i;
    }
    return -1;
  }

  /// Forgets every placement. Call when the premise changes — a different
  /// item list, column count, spacing, or cross-axis extent.
  void reset() {
    _slots.clear();
    for (int i = 0; i < _columnEnd.length; i++) {
      _columnEnd[i] = 0;
    }
  }
}
