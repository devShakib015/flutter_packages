import 'package:flutter/widgets.dart';

import 'render_sliver_masonry_grid.dart';

/// A sliver that arranges its children in columns, each child going into
/// whichever column is currently shortest.
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     SliverMasonryGrid.count(
///       crossAxisCount: 2,
///       childCount: photos.length,
///       itemBuilder: (context, index) => Photo(photos[index]),
///     ),
///   ],
/// )
/// ```
///
/// Several of these can share one [CustomScrollView]. That sounds like a low
/// bar, and it is the reason this package exists: a masonry sliver that
/// revises its own geometry mid-scroll must ask the viewport for a
/// `scrollOffsetCorrection`, which restarts the layout pass — and with two
/// such slivers the corrections interfere and throw the reader backwards. This
/// one measures each item once, remembers where it went, and never revises.
class SliverMasonryGrid extends SliverMultiBoxAdaptorWidget {
  /// Creates a masonry sliver with a fixed number of columns.
  SliverMasonryGrid.count({
    super.key,
    required this.crossAxisCount,
    required int childCount,
    required IndexedWidgetBuilder itemBuilder,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    ChildIndexGetter? findChildIndexCallback,
  }) : _maxCrossAxisExtent = null,
       assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
       assert(childCount >= 0, 'childCount cannot be negative'),
       assert(mainAxisSpacing >= 0, 'mainAxisSpacing cannot be negative'),
       assert(crossAxisSpacing >= 0, 'crossAxisSpacing cannot be negative'),
       super(
         delegate: SliverChildBuilderDelegate(
           itemBuilder,
           childCount: childCount,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
           addRepaintBoundaries: addRepaintBoundaries,
           addSemanticIndexes: addSemanticIndexes,
           findChildIndexCallback: findChildIndexCallback,
         ),
       );

  /// Creates a masonry sliver from an explicit list of children.
  SliverMasonryGrid.list({
    super.key,
    required this.crossAxisCount,
    required List<Widget> children,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
  }) : _maxCrossAxisExtent = null,
       assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
       assert(mainAxisSpacing >= 0, 'mainAxisSpacing cannot be negative'),
       assert(crossAxisSpacing >= 0, 'crossAxisSpacing cannot be negative'),
       super(
         delegate: SliverChildListDelegate(
           children,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
           addRepaintBoundaries: addRepaintBoundaries,
           addSemanticIndexes: addSemanticIndexes,
         ),
       );

  /// Creates a masonry sliver whose columns are as many as will fit without
  /// any exceeding [maxCrossAxisExtent].
  ///
  /// Use this rather than [SliverMasonryGrid.count] when the same screen has
  /// to work on a phone and a tablet: a fixed count either wastes a wide
  /// window or squeezes a narrow one.
  SliverMasonryGrid.extent({
    super.key,
    required double maxCrossAxisExtent,
    required int childCount,
    required IndexedWidgetBuilder itemBuilder,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
    bool addAutomaticKeepAlives = true,
    bool addRepaintBoundaries = true,
    bool addSemanticIndexes = true,
    ChildIndexGetter? findChildIndexCallback,
  }) : crossAxisCount = 1,
       _maxCrossAxisExtent = maxCrossAxisExtent,
       assert(maxCrossAxisExtent > 0, 'maxCrossAxisExtent must be positive'),
       assert(childCount >= 0, 'childCount cannot be negative'),
       assert(mainAxisSpacing >= 0, 'mainAxisSpacing cannot be negative'),
       assert(crossAxisSpacing >= 0, 'crossAxisSpacing cannot be negative'),
       super(
         delegate: SliverChildBuilderDelegate(
           itemBuilder,
           childCount: childCount,
           addAutomaticKeepAlives: addAutomaticKeepAlives,
           addRepaintBoundaries: addRepaintBoundaries,
           addSemanticIndexes: addSemanticIndexes,
           findChildIndexCallback: findChildIndexCallback,
         ),
       );

  /// Creates a masonry sliver from an arbitrary [delegate].
  const SliverMasonryGrid.custom({
    super.key,
    required this.crossAxisCount,
    required super.delegate,
    this.mainAxisSpacing = 0,
    this.crossAxisSpacing = 0,
  }) : _maxCrossAxisExtent = null,
       assert(crossAxisCount > 0, 'crossAxisCount must be positive'),
       assert(mainAxisSpacing >= 0, 'mainAxisSpacing cannot be negative'),
       assert(crossAxisSpacing >= 0, 'crossAxisSpacing cannot be negative');

  /// How many columns to distribute children across, when a fixed count was
  /// asked for.
  final int crossAxisCount;

  final double? _maxCrossAxisExtent;

  /// Gap between two children in the same column.
  final double mainAxisSpacing;

  /// Gap between columns.
  final double crossAxisSpacing;

  @override
  RenderSliverMasonryGrid createRenderObject(BuildContext context) {
    final SliverMultiBoxAdaptorElement element =
        context as SliverMultiBoxAdaptorElement;
    return RenderSliverMasonryGrid(
      childManager: element,
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainAxisSpacing,
      crossAxisSpacing: crossAxisSpacing,
      maxCrossAxisExtent: _maxCrossAxisExtent,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSliverMasonryGrid renderObject,
  ) {
    renderObject
      ..crossAxisCount = crossAxisCount
      ..maxCrossAxisExtent = _maxCrossAxisExtent
      ..mainAxisSpacing = mainAxisSpacing
      ..crossAxisSpacing = crossAxisSpacing;
  }

  @override
  SliverMultiBoxAdaptorElement createElement() => _MasonryElement(this);
}

/// Notices when the delegate's children change so the cached placements, which
/// were only ever valid for one particular list, are thrown away.
class _MasonryElement extends SliverMultiBoxAdaptorElement {
  _MasonryElement(SliverMasonryGrid super.widget);

  @override
  void update(SliverMasonryGrid newWidget) {
    final SliverChildDelegate oldDelegate =
        (widget as SliverMasonryGrid).delegate;
    super.update(newWidget);
    final SliverChildDelegate newDelegate = newWidget.delegate;
    if (newDelegate != oldDelegate &&
        (newDelegate.runtimeType != oldDelegate.runtimeType ||
            newDelegate.shouldRebuild(oldDelegate))) {
      (renderObject as RenderSliverMasonryGrid).invalidateItemLayout();
    }
  }
}
