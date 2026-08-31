import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'masonry_layout.dart';

/// Parent data for a masonry child: the usual sliver fields plus which column
/// the child landed in.
class SliverMasonryGridParentData extends SliverMultiBoxAdaptorParentData {
  /// Distance from the leading cross-axis edge to this child's leading edge.
  double crossAxisOffset = 0;

  @override
  String toString() => 'crossAxisOffset=$crossAxisOffset; ${super.toString()}';
}

/// A sliver that lays children out in columns, each new child going into
/// whichever column is currently shortest.
///
/// The layout is computed once per item and never revised — see
/// [MasonryLayout]. That is the difference that matters: a sliver which
/// revises its own geometry mid-scroll has to ask the viewport for a
/// `scrollOffsetCorrection`, the viewport restarts the whole layout pass, and
/// with more than one such sliver in the same [CustomScrollView] the
/// corrections interfere and throw the reader backwards. This sliver never
/// issues one.
class RenderSliverMasonryGrid extends RenderSliverMultiBoxAdaptor {
  /// Creates a masonry sliver.
  RenderSliverMasonryGrid({
    required super.childManager,
    required int crossAxisCount,
    required double mainAxisSpacing,
    required double crossAxisSpacing,
    double? maxCrossAxisExtent,
  }) : // The field is private but the parameter must stay public for callers.
       // ignore: prefer_initializing_formals
       _maxCrossAxisExtent = maxCrossAxisExtent,
       assert(crossAxisCount > 0),
       assert(mainAxisSpacing >= 0),
       assert(crossAxisSpacing >= 0),
       _crossAxisCount = crossAxisCount,
       _mainAxisSpacing = mainAxisSpacing,
       _crossAxisSpacing = crossAxisSpacing;

  MasonryLayout? _layout;

  /// Cross-axis extent the cache was built against; a change invalidates it.
  double _layoutCrossAxisExtent = double.nan;

  /// The widest a column may be, or null to use a fixed [crossAxisCount].
  ///
  /// When set, the column count is derived from the space available, the way
  /// `GridView.extent` does it — which is what a photo grid wants when the
  /// same code runs on a phone and a tablet.
  double? get maxCrossAxisExtent => _maxCrossAxisExtent;
  double? _maxCrossAxisExtent;
  set maxCrossAxisExtent(double? value) {
    if (_maxCrossAxisExtent == value) return;
    _maxCrossAxisExtent = value;
    _invalidateLayout();
  }

  /// Columns actually used for [crossAxisExtent], honouring
  /// [maxCrossAxisExtent] when one is set.
  int columnsFor(double crossAxisExtent) {
    final double? max = _maxCrossAxisExtent;
    if (max == null) return _crossAxisCount;
    // Matches SliverGridDelegateWithMaxCrossAxisExtent: as many columns as fit
    // without any exceeding the maximum.
    return math.max(
      1,
      ((crossAxisExtent + _crossAxisSpacing) / (max + _crossAxisSpacing))
          .ceil(),
    );
  }

  /// Number of columns when [maxCrossAxisExtent] is null.
  int get crossAxisCount => _crossAxisCount;
  int _crossAxisCount;
  set crossAxisCount(int value) {
    assert(value > 0);
    if (_crossAxisCount == value) return;
    _crossAxisCount = value;
    _invalidateLayout();
  }

  /// Gap between two items in the same column.
  double get mainAxisSpacing => _mainAxisSpacing;
  double _mainAxisSpacing;
  set mainAxisSpacing(double value) {
    assert(value >= 0);
    if (_mainAxisSpacing == value) return;
    _mainAxisSpacing = value;
    _invalidateLayout();
  }

  /// Gap between columns.
  double get crossAxisSpacing => _crossAxisSpacing;
  double _crossAxisSpacing;
  set crossAxisSpacing(double value) {
    assert(value >= 0);
    if (_crossAxisSpacing == value) return;
    _crossAxisSpacing = value;
    _invalidateLayout();
  }

  void _invalidateLayout() {
    _layout = null;
    markNeedsLayout();
  }

  /// Discards the cache because the items themselves changed.
  ///
  /// Called by the widget when the delegate reports that children moved, since
  /// a placement is only final while the list it was computed from is.
  void invalidateItemLayout() => _invalidateLayout();

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverMasonryGridParentData) {
      child.parentData = SliverMasonryGridParentData();
    }
  }

  SliverMasonryGridParentData _parentDataOf(RenderBox child) =>
      child.parentData! as SliverMasonryGridParentData;

  @override
  double childCrossAxisPosition(RenderBox child) =>
      _parentDataOf(child).crossAxisOffset;

  double _childCrossAxisExtent(double crossAxisExtent) {
    final int columns = columnsFor(crossAxisExtent);
    return (crossAxisExtent - _crossAxisSpacing * (columns - 1)) / columns;
  }

  double _crossAxisOffsetFor(int column, double childCrossAxisExtent) =>
      column * (childCrossAxisExtent + _crossAxisSpacing);

  BoxConstraints _childConstraints(double childCrossAxisExtent) {
    // Tight across, free along the scroll axis: the measured extent is
    // precisely what masonry needs from each child.
    return switch (constraints.axis) {
      Axis.vertical => BoxConstraints.tightFor(width: childCrossAxisExtent),
      Axis.horizontal => BoxConstraints.tightFor(height: childCrossAxisExtent),
    };
  }

  double _mainExtentOf(RenderBox child) => switch (constraints.axis) {
    Axis.vertical => child.size.height,
    Axis.horizontal => child.size.width,
  };

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final double crossAxisExtent = constraints.crossAxisExtent;
    final double childCrossAxisExtent = _childCrossAxisExtent(crossAxisExtent);

    // The cache is only valid for the geometry it was measured under.
    if (_layout == null || _layoutCrossAxisExtent != crossAxisExtent) {
      _layout = MasonryLayout(
        crossAxisCount: columnsFor(crossAxisExtent),
        mainAxisSpacing: _mainAxisSpacing,
      );
      _layoutCrossAxisExtent = crossAxisExtent;
      // Children left over from the old cache are holding arbitrary indices.
      // Measuring from wherever they happen to sit would place the wrong
      // heights at the wrong indices, so start the child list over as well.
      _discardAllChildren();
    }
    final MasonryLayout layout = _layout!;
    final BoxConstraints childConstraints = _childConstraints(
      childCrossAxisExtent,
    );

    final double windowStart = math.max(
      0,
      constraints.scrollOffset + constraints.cacheOrigin,
    );
    final double windowEnd = windowStart + constraints.remainingCacheExtent;

    if (childManager.childCount == 0) {
      _reportEmpty();
      childManager.didFinishLayout();
      return;
    }

    // 1. Grow the cache until it covers the window, or runs out of items.
    //
    // Masonry is sequential, so this walks forward from wherever the cache
    // ended. During ordinary scrolling that is a screenful at a time. The
    // children created here are temporary scaffolding; step 3 releases the
    // ones the window does not want.
    final int measuredBefore = layout.count;
    while (layout.shortestColumnExtent < windowEnd &&
        layout.count < childManager.childCount) {
      // Walk the child list forward rather than assuming it already ends
      // where the cache does — after a window jump it can trail well behind,
      // and inserting after the wrong child would misindex everything.
      final int index = lastChild == null ? 0 : indexOf(lastChild!) + 1;
      if (index >= childManager.childCount) break;
      final RenderBox? child = index == 0
          ? _addFirstChild(childConstraints)
          : insertAndLayoutChild(
              childConstraints,
              after: lastChild,
              parentUsesSize: true,
            );
      if (child == null) break; // The manager has no more to give.
      if (index == layout.count) {
        // New ground: measure it and commit the placement, once and for all.
        _place(
          child,
          index,
          layout.append(_mainExtentOf(child)),
          childCrossAxisExtent,
        );
      } else {
        // Already placed on an earlier pass. Reuse that answer verbatim.
        _place(child, index, layout.slotOf(index), childCrossAxisExtent);
      }
    }

    if (layout.isEmpty) {
      _reportEmpty();
      childManager.didFinishLayout();
      return;
    }

    // 2. Which items does the window actually want?
    final int firstIndex = math.min(
      layout.firstIndexAfter(windowStart),
      layout.count - 1,
    );
    final int lastIndex = math.max(
      layout.lastIndexBefore(windowEnd),
      firstIndex,
    );

    // 3. Make the child list exactly [firstIndex, lastIndex].
    _reconcileChildren(
      firstIndex: firstIndex,
      lastIndex: lastIndex,
      childConstraints: childConstraints,
      layout: layout,
      childCrossAxisExtent: childCrossAxisExtent,
      grewCacheThisPass: layout.count > measuredBefore,
    );

    // 4. Report geometry. No correction is ever requested: every offset came
    //    from the cache, so there is nothing to take back.
    final bool reachedEnd = layout.count >= childManager.childCount;
    final double scrollExtent = reachedEnd
        ? layout.extent
        : _estimateTotalExtent(layout);

    final double leading = layout.slotOf(firstIndex).offset;
    double trailing = 0;
    for (int i = firstIndex; i <= lastIndex; i++) {
      trailing = math.max(trailing, layout.slotOf(i).end);
    }

    final double paintExtent = calculatePaintOffset(
      constraints,
      from: leading,
      to: trailing,
    );
    final double cacheExtent = calculateCacheOffset(
      constraints,
      from: leading,
      to: trailing,
    );

    geometry = SliverGeometry(
      scrollExtent: scrollExtent,
      paintExtent: paintExtent,
      cacheExtent: cacheExtent,
      maxPaintExtent: scrollExtent,
      hasVisualOverflow:
          trailing >
              constraints.scrollOffset + constraints.remainingPaintExtent ||
          constraints.scrollOffset > 0,
    );

    if (reachedEnd && trailing >= scrollExtent) {
      childManager.setDidUnderflow(true);
    }
    childManager.didFinishLayout();
  }

  /// Empties the live child list. Used when the cache is thrown away, since
  /// the two have to agree on what index each child holds.
  void _discardAllChildren() {
    int count = 0;
    for (RenderBox? c = firstChild; c != null; c = childAfter(c)) {
      count++;
    }
    if (count > 0) collectGarbage(count, 0);
  }

  RenderBox? _addFirstChild(BoxConstraints childConstraints) {
    if (firstChild == null) {
      if (!addInitialChild()) return null;
    }
    firstChild!.layout(childConstraints, parentUsesSize: true);
    return firstChild;
  }

  void _place(
    RenderBox child,
    int index,
    MasonrySlot slot,
    double childCrossAxisExtent,
  ) {
    final SliverMasonryGridParentData data = _parentDataOf(child);
    data.layoutOffset = slot.offset;
    data.crossAxisOffset = _crossAxisOffsetFor(
      slot.column,
      childCrossAxisExtent,
    );
  }

  /// Brings the live child list to exactly [firstIndex]..[lastIndex].
  void _reconcileChildren({
    required int firstIndex,
    required int lastIndex,
    required BoxConstraints childConstraints,
    required MasonryLayout layout,
    required double childCrossAxisExtent,
    required bool grewCacheThisPass,
  }) {
    // Drop what fell outside the window.
    int leadingGarbage = 0;
    int trailingGarbage = 0;
    RenderBox? child = firstChild;
    while (child != null && indexOf(child) < firstIndex) {
      leadingGarbage++;
      child = childAfter(child);
    }
    child = lastChild;
    while (child != null && indexOf(child) > lastIndex) {
      trailingGarbage++;
      child = childBefore(child);
    }
    if (leadingGarbage > 0 || trailingGarbage > 0) {
      collectGarbage(leadingGarbage, trailingGarbage);
    }

    if (firstChild == null) {
      // Everything was collected, or nothing existed. Re-seed at firstIndex;
      // its slot is already known, so this cannot move anything.
      if (!addInitialChild(
        index: firstIndex,
        layoutOffset: layout.slotOf(firstIndex).offset,
      )) {
        return;
      }
      firstChild!.layout(childConstraints, parentUsesSize: true);
      _place(
        firstChild!,
        firstIndex,
        layout.slotOf(firstIndex),
        childCrossAxisExtent,
      );
    }

    // Fill in backwards to firstIndex.
    while (indexOf(firstChild!) > firstIndex) {
      final RenderBox? added = insertAndLayoutLeadingChild(
        childConstraints,
        parentUsesSize: true,
      );
      if (added == null) break;
      final int index = indexOf(added);
      _place(added, index, layout.slotOf(index), childCrossAxisExtent);
    }

    // And forwards to lastIndex.
    while (indexOf(lastChild!) < lastIndex) {
      final RenderBox? added = insertAndLayoutChild(
        childConstraints,
        after: lastChild,
        parentUsesSize: true,
      );
      if (added == null) break;
      final int index = indexOf(added);
      _place(added, index, layout.slotOf(index), childCrossAxisExtent);
    }

    // Children carried over from the previous pass were laid out then, but
    // their parent data still needs restating if the cache was rebuilt.
    RenderBox? walk = firstChild;
    while (walk != null) {
      final int index = indexOf(walk);
      if (index < layout.count) {
        if (grewCacheThisPass || _parentDataOf(walk).layoutOffset == null) {
          walk.layout(childConstraints, parentUsesSize: true);
        }
        _place(walk, index, layout.slotOf(index), childCrossAxisExtent);
      }
      walk = childAfter(walk);
    }
  }

  /// Extrapolates the full extent from what has been measured.
  ///
  /// Averaging over measured *items* and dividing by the column count is what
  /// keeps this stable: the estimate moves as the average settles, not as the
  /// tallest column changes hands.
  double _estimateTotalExtent(MasonryLayout layout) {
    final int total = childManager.childCount;
    final int measured = layout.count;
    if (measured == 0) return 0;
    double sum = 0;
    for (int i = 0; i < measured; i++) {
      sum += layout.slotOf(i).extent + _mainAxisSpacing;
    }
    final double averagePerItem = sum / measured;
    final double remaining = (total - measured) * averagePerItem;
    return layout.extent + remaining / layout.crossAxisCount;
  }

  void _reportEmpty() {
    geometry = SliverGeometry.zero;
    childManager.setDidUnderflow(true);
  }

  @override
  double childMainAxisPosition(RenderBox child) =>
      childScrollOffset(child)! - constraints.scrollOffset;

  @override
  double? childScrollOffset(RenderBox child) =>
      _parentDataOf(child).layoutOffset;
}
