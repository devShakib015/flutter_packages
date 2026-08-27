import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'sliver_masonry_grid.dart';

/// A scrollable masonry grid — children flow into whichever column is
/// currently shortest, and keep the place they were given.
///
/// ```dart
/// MasonryGridView.count(
///   crossAxisCount: 2,
///   mainAxisSpacing: 8,
///   crossAxisSpacing: 8,
///   itemCount: photos.length,
///   itemBuilder: (context, index) => Photo(photos[index]),
/// )
/// ```
///
/// This is the box-widget convenience; [SliverMasonryGrid] is the same layout
/// for a [CustomScrollView], and unlike the package this replaces, you can put
/// more than one of those in a single scroll view.
class MasonryGridView extends BoxScrollView {
  /// Creates a scrollable masonry grid with a fixed number of columns.
  const MasonryGridView.count({
    super.key,
    required this.crossAxisCount,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.findChildIndexCallback,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    // Renamed to scrollCacheExtent after Flutter 3.41; our floor is 3.32.
    // ignore: deprecated_member_use
    super.cacheExtent,
    super.dragStartBehavior = DragStartBehavior.start,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    int? semanticChildCount,
  }) : _itemCount = itemCount,
       // ignore: prefer_initializing_formals
       _itemBuilder = itemBuilder,
       _children = null,
       assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
       assert(itemCount >= 0, 'itemCount cannot be negative'),
       super(semanticChildCount: semanticChildCount ?? itemCount);

  /// Creates a scrollable masonry grid from an explicit list of children.
  const MasonryGridView({
    super.key,
    required this.crossAxisCount,
    required List<Widget> children,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    // Renamed to scrollCacheExtent after Flutter 3.41; our floor is 3.32.
    // ignore: deprecated_member_use
    super.cacheExtent,
    super.dragStartBehavior = DragStartBehavior.start,
    super.keyboardDismissBehavior,
    super.restorationId,
    super.clipBehavior,
    int? semanticChildCount,
  }) : _children = children,
       _itemCount = children.length,
       _itemBuilder = null,
       findChildIndexCallback = null,
       assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
       super(semanticChildCount: semanticChildCount ?? children.length);

  /// How many columns to distribute children across.
  final int crossAxisCount;

  /// Gap between two children in the same column.
  final double mainAxisSpacing;

  /// Gap between columns.
  final double crossAxisSpacing;

  /// Whether to wrap children in automatic keep-alives.
  final bool addAutomaticKeepAlives;

  /// Whether to wrap children in repaint boundaries.
  final bool addRepaintBoundaries;

  /// Whether to attach semantic indexes to children.
  final bool addSemanticIndexes;

  /// Locates a child by key so its state survives insertions.
  final ChildIndexGetter? findChildIndexCallback;

  final int _itemCount;
  final IndexedWidgetBuilder? _itemBuilder;
  final List<Widget>? _children;

  @override
  Widget buildChildLayout(BuildContext context) {
    final List<Widget>? children = _children;
    if (children != null) {
      return SliverMasonryGrid.list(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: mainAxisSpacing,
        crossAxisSpacing: crossAxisSpacing,
        addAutomaticKeepAlives: addAutomaticKeepAlives,
        addRepaintBoundaries: addRepaintBoundaries,
        addSemanticIndexes: addSemanticIndexes,
        children: children,
      );
    }
    return SliverMasonryGrid.count(
      crossAxisCount: crossAxisCount,
      childCount: _itemCount,
      itemBuilder: _itemBuilder!,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
      findChildIndexCallback: findChildIndexCallback,
    );
  }
}
