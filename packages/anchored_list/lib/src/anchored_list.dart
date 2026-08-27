import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'anchored_list_controller.dart';
import 'item_position.dart';

/// A lazy list that can jump to any index instantly.
///
/// ```dart
/// AnchoredList.builder(
///   controller: controller,
///   itemCount: 100000,
///   itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
/// )
///
/// controller.jumpToIndex(84213);
/// ```
///
/// ## How it works, and why that matters
///
/// Scrolling to an arbitrary index is hard because a lazy list does not know
/// how tall its unbuilt items are, so it cannot say where item 84,213 begins.
/// The established workaround builds a *second* list anchored at the target
/// and cross-fades to it, which means two sets of children alive during every
/// jump and a visible transition.
///
/// This takes the other route. A Flutter viewport already supports a **centre
/// sliver**, with content before it laid out at negative scroll offset. So the
/// list splits in two at the anchor: items before it in one sliver, the anchor
/// and everything after in another, marked as the centre. Offset zero *is* the
/// anchor.
///
/// Jumping is then just re-splitting, which costs the same whether you move
/// three items or three hundred thousand. One viewport, one set of children,
/// no cross-fade.
///
/// ## The trade
///
/// `shrinkWrap` is **not supported**, and cannot be: Flutter asserts
/// `!shrinkWrap || center == null`, so a centre-anchored viewport can never
/// size itself to its content. If you need a list that shrink-wraps, this is
/// the wrong widget — use [ListView] with `shrinkWrap: true` and accept that
/// jumping to a far index is not constant time.
///
/// Nor is this a sliver, so it cannot be placed inside another
/// [CustomScrollView]. It owns its viewport, because owning the viewport is
/// what makes the centre trick possible.
class AnchoredList extends StatefulWidget {
  /// Creates a lazily-built anchored list.
  const AnchoredList.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.initialIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.padding,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
  }) : assert(itemCount >= 0, 'itemCount cannot be negative'),
       assert(initialIndex >= 0, 'initialIndex cannot be negative'),
       assert(
         initialAlignment >= 0 && initialAlignment <= 1,
         'initialAlignment must be 0..1',
       );

  /// How many items the list has.
  final int itemCount;

  /// Builds the item at an index. Called lazily, as items come into view.
  final IndexedWidgetBuilder itemBuilder;

  /// Drives jumps and reports positions.
  final AnchoredListController? controller;

  /// The index shown when the list first builds.
  ///
  /// Free at any value: starting at item 500,000 costs no more than item 0,
  /// because nothing before the anchor is ever built.
  final int initialIndex;

  /// Where [initialIndex] sits in the viewport. 0 is the leading edge.
  final double initialAlignment;

  /// The axis the list scrolls along.
  final Axis scrollDirection;

  /// Whether the list is reversed.
  final bool reverse;

  /// How the list responds to user input.
  final ScrollPhysics? physics;

  /// Space around the list's contents.
  final EdgeInsetsGeometry? padding;

  /// Whether to wrap children in automatic keep-alives.
  final bool addAutomaticKeepAlives;

  /// Whether to wrap children in repaint boundaries.
  final bool addRepaintBoundaries;

  /// Whether to attach semantic indexes to children.
  final bool addSemanticIndexes;

  /// How to clip contents that overflow.
  final Clip clipBehavior;

  /// Restoration id for the scroll position.
  final String? restorationId;

  @override
  State<AnchoredList> createState() => _AnchoredListState();
}

class _AnchoredListState extends State<AnchoredList>
    implements AnchoredListBinding {
  /// Marks the sliver that owns scroll offset zero.
  final Key _centreKey = UniqueKey();

  final ScrollController _scroll = ScrollController();

  /// Contexts of items currently built, by list index.
  ///
  /// Kept so movement can hand a real element to [Scrollable.ensureVisible]
  /// rather than reimplementing offset arithmetic over sliver internals.
  final Map<int, BuildContext> _built = <int, BuildContext>{};

  late int _anchorIndex = _clamp(widget.initialIndex);
  late double _alignment = widget.initialAlignment;
  bool _positionsScheduled = false;

  int _clamp(int index) =>
      widget.itemCount == 0 ? 0 : index.clamp(0, widget.itemCount - 1);

  @override
  int get anchorIndex => _anchorIndex;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    _scroll.addListener(_schedulePositions);
  }

  @override
  void didUpdateWidget(AnchoredList old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
    if (widget.itemCount != old.itemCount) {
      _anchorIndex = _clamp(_anchorIndex);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(this);
    _scroll
      ..removeListener(_schedulePositions)
      ..dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- movement

  @override
  void jumpToIndex(int index, double alignment) {
    if (widget.itemCount == 0) return;
    setState(() {
      _anchorIndex = _clamp(index);
      _alignment = alignment;
    });
    // Offset zero means "the anchor", and the anchor just moved, so the
    // position has to return to zero for the new split to be what is shown.
    if (_scroll.hasClients && _scroll.offset != 0) _scroll.jumpTo(0);
    _schedulePositions();
  }

  @override
  Future<void> animateToIndex(
    int index,
    double alignment,
    Duration duration,
    Curve curve,
  ) async {
    if (widget.itemCount == 0) return;
    final int target = _clamp(index);

    // Only built content can be scrolled *through*; beyond it the extents are
    // unknown. So land near the target first, then animate the last stretch —
    // a fast scroll rather than a cross-fade between two lists.
    if (!_built.containsKey(target)) {
      const int approach = 10;
      final int staging = target > _anchorIndex
          ? math.max(0, target - approach)
          : math.min(widget.itemCount - 1, target + approach);
      jumpToIndex(staging, alignment);
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final BuildContext? item = _built[target];
    if (item == null || !item.mounted) {
      jumpToIndex(target, alignment);
      return;
    }
    if (_alignment != alignment) {
      setState(() => _alignment = alignment);
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !item.mounted) return;
    }
    await Scrollable.ensureVisible(
      item,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
    _schedulePositions();
  }

  // ------------------------------------------------------------- positions

  void _schedulePositions() {
    if (widget.controller == null || _positionsScheduled) return;
    _positionsScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _positionsScheduled = false;
      if (mounted) widget.controller?.publishPositions(_currentPositions());
    });
  }

  List<ItemPosition> _currentPositions() {
    final RenderObject? self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return const <ItemPosition>[];

    final double viewportExtent = widget.scrollDirection == Axis.vertical
        ? self.size.height
        : self.size.width;
    if (viewportExtent <= 0) return const <ItemPosition>[];

    final List<ItemPosition> out = <ItemPosition>[];
    for (final MapEntry<int, BuildContext> entry in _built.entries) {
      if (!entry.value.mounted) continue;
      final RenderObject? box = entry.value.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;

      final Offset origin = box.localToGlobal(Offset.zero, ancestor: self);
      final double lead = widget.scrollDirection == Axis.vertical
          ? origin.dy
          : origin.dx;
      final double size = widget.scrollDirection == Axis.vertical
          ? box.size.height
          : box.size.width;

      out.add(
        ItemPosition(
          index: entry.key,
          leadingEdge: lead / viewportExtent,
          trailingEdge: (lead + size) / viewportExtent,
        ),
      );
    }
    out.sort((ItemPosition a, ItemPosition b) => a.index.compareTo(b.index));
    return out;
  }

  // ---------------------------------------------------------------- build

  Widget _item(BuildContext _, int index) => _RegisteredItem(
    index: index,
    registry: _built,
    onMounted: _schedulePositions,
    builder: widget.itemBuilder,
  );

  @override
  Widget build(BuildContext context) {
    final int leading = _anchorIndex;
    final int trailing = math.max(0, widget.itemCount - _anchorIndex);

    return CustomScrollView(
      controller: _scroll,
      // Offset zero lives here: the sliver that starts at the anchor.
      center: _centreKey,
      anchor: _alignment,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      physics: widget.physics,
      clipBehavior: widget.clipBehavior,
      restorationId: widget.restorationId,
      slivers: <Widget>[
        // Everything before the anchor, built backwards into negative offset.
        SliverPadding(
          padding: _leadingPadding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext c, int i) => _item(c, _anchorIndex - 1 - i),
              childCount: leading,
              addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
              addRepaintBoundaries: widget.addRepaintBoundaries,
              addSemanticIndexes: widget.addSemanticIndexes,
            ),
          ),
        ),
        // The anchor and everything after it.
        SliverPadding(
          key: _centreKey,
          padding: _trailingPadding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext c, int i) => _item(c, _anchorIndex + i),
              childCount: trailing,
              addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
              addRepaintBoundaries: widget.addRepaintBoundaries,
              addSemanticIndexes: widget.addSemanticIndexes,
            ),
          ),
        ),
      ],
    );
  }

  /// Padding is split between the two slivers — applying the whole inset to
  /// both would double it in the middle.
  EdgeInsets get _leadingPadding => widget.scrollDirection == Axis.vertical
      ? _padding.copyWith(bottom: 0)
      : _padding.copyWith(right: 0);

  EdgeInsets get _trailingPadding => widget.scrollDirection == Axis.vertical
      ? _padding.copyWith(top: 0)
      : _padding.copyWith(left: 0);

  EdgeInsets get _padding =>
      widget.padding?.resolve(Directionality.maybeOf(context)) ??
      EdgeInsets.zero;
}

/// Wraps one item so the list knows it exists and where it is.
class _RegisteredItem extends StatefulWidget {
  const _RegisteredItem({
    required this.index,
    required this.registry,
    required this.onMounted,
    required this.builder,
  });

  final int index;
  final Map<int, BuildContext> registry;
  final VoidCallback onMounted;
  final IndexedWidgetBuilder builder;

  @override
  State<_RegisteredItem> createState() => _RegisteredItemState();
}

class _RegisteredItemState extends State<_RegisteredItem> {
  @override
  void initState() {
    super.initState();
    widget.registry[widget.index] = context;
    widget.onMounted();
  }

  @override
  void didUpdateWidget(_RegisteredItem old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (widget.registry[old.index] == context) {
        widget.registry.remove(old.index);
      }
      widget.registry[widget.index] = context;
    }
  }

  @override
  void dispose() {
    if (widget.registry[widget.index] == context) {
      widget.registry.remove(widget.index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.index);
}
