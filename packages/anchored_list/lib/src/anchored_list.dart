import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'anchored_list_controller.dart';
import 'item_position.dart';

part 'reorder.dart';

/// Matches the framework's own reorderable lists, so a drag near the edge
/// scrolls at the speed people already expect.
const double _kDefaultAutoScrollVelocityScalar = 50;

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
/// The same split pays off a second time when items arrive at the top of the
/// list: because the anchor is an index rather than a pixel offset, correcting
/// for a prepended page is arithmetic on one integer. See
/// [AnchoredListController.itemsInsertedAbove].
///
/// It pays off a third time in reordering, which is why that lives here at
/// all. The registry of built items is keyed by *list* index and does not know
/// which sliver an item is in, so a drag crosses the anchor without noticing
/// it — where a `SliverReorderableList` in each half would be two separate
/// reorder domains. See [onReorder].
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
  /// Creates an anchored list from an explicit list of [children].
  ///
  /// Every child is built up front, exactly as with [ListView]'s default
  /// constructor. Prefer [AnchoredList.builder] for anything long.
  AnchoredList({
    super.key,
    required List<Widget> children,
    this.controller,
    this.scrollController,
    this.initialIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.padding,
    this.cacheExtent,
    this.semanticChildCount,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.scrollBehavior,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.proxyDecorator,
    this.longPressToDrag = true,
    this.autoScrollerVelocityScalar = _kDefaultAutoScrollVelocityScalar,
  })  : itemCount = children.length,
        itemBuilder = ((BuildContext _, int index) => children[index]),
        separatorBuilder = null,
        findChildIndexCallback = null,
        assert(initialIndex >= 0, 'initialIndex cannot be negative'),
        assert(
          initialAlignment >= 0 && initialAlignment <= 1,
          'initialAlignment must be 0..1',
        );

  /// Creates a lazily-built anchored list.
  const AnchoredList.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.scrollController,
    this.initialIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.padding,
    this.cacheExtent,
    this.semanticChildCount,
    this.findChildIndexCallback,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.scrollBehavior,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.proxyDecorator,
    this.longPressToDrag = true,
    this.autoScrollerVelocityScalar = _kDefaultAutoScrollVelocityScalar,
  })  : separatorBuilder = null,
        assert(itemCount >= 0, 'itemCount cannot be negative'),
        assert(initialIndex >= 0, 'initialIndex cannot be negative'),
        assert(
          initialAlignment >= 0 && initialAlignment <= 1,
          'initialAlignment must be 0..1',
        );

  /// Creates a lazily-built anchored list with a separator between items.
  ///
  /// [separatorBuilder] is called with the index of the item *above* the
  /// separator, so it runs `itemCount - 1` times, matching
  /// [ListView.separated].
  const AnchoredList.separated({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required IndexedWidgetBuilder this.separatorBuilder,
    this.controller,
    this.scrollController,
    this.initialIndex = 0,
    this.initialAlignment = 0,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.physics,
    this.padding,
    this.cacheExtent,
    this.semanticChildCount,
    this.findChildIndexCallback,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true,
    this.addSemanticIndexes = true,
    this.dragStartBehavior = DragStartBehavior.start,
    this.keyboardDismissBehavior = ScrollViewKeyboardDismissBehavior.manual,
    this.scrollBehavior,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.onReorder,
    this.onReorderStart,
    this.onReorderEnd,
    this.proxyDecorator,
    this.longPressToDrag = true,
    this.autoScrollerVelocityScalar = _kDefaultAutoScrollVelocityScalar,
  })  : assert(itemCount >= 0, 'itemCount cannot be negative'),
        assert(initialIndex >= 0, 'initialIndex cannot be negative'),
        assert(
          initialAlignment >= 0 && initialAlignment <= 1,
          'initialAlignment must be 0..1',
        );

  /// How many items the list has.
  final int itemCount;

  /// Builds the item at an index. Called lazily, as items come into view.
  final IndexedWidgetBuilder itemBuilder;

  /// Builds the separator below item `index`, or null when there is none.
  final IndexedWidgetBuilder? separatorBuilder;

  /// Drives jumps and reports positions.
  final AnchoredListController? controller;

  /// The scroll controller for the underlying viewport.
  ///
  /// Supply one to attach a [Scrollbar], link two lists, or drive the list by
  /// pixel offset. One is created internally when this is null, and either way
  /// [AnchoredListController.scrollController] hands back the live one.
  ///
  /// Remember that offsets are relative to the anchor, not the start of the
  /// list — see [AnchoredListController.scrollController].
  final ScrollController? scrollController;

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

  /// How far beyond the viewport to build, in pixels.
  final double? cacheExtent;

  /// The number of children the semantics tree reports. Defaults to
  /// [itemCount].
  final int? semanticChildCount;

  /// Locates an item by [Key] so its state survives insertions and reordering.
  ///
  /// Return the item's **list index**, exactly as you would for
  /// [ListView.builder]; the split into two slivers is translated for you.
  final ChildIndexGetter? findChildIndexCallback;

  /// Whether to wrap children in automatic keep-alives.
  final bool addAutomaticKeepAlives;

  /// Whether to wrap children in repaint boundaries.
  final bool addRepaintBoundaries;

  /// Whether to attach semantic indexes to children.
  final bool addSemanticIndexes;

  /// When a drag formally begins.
  final DragStartBehavior dragStartBehavior;

  /// Whether dragging dismisses the on-screen keyboard.
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  /// Overrides the ambient scroll behaviour, e.g. to hide desktop scrollbars.
  final ScrollBehavior? scrollBehavior;

  /// How to clip contents that overflow.
  final Clip clipBehavior;

  /// Restoration id for the scroll position.
  final String? restorationId;

  /// Called when a drag drops an item somewhere new. Non-null turns
  /// reordering on.
  ///
  /// Move the item in your own data and rebuild, exactly as with
  /// [ReorderableListView] — `newIndex` counts with the dragged item still in
  /// place, so a move down the list needs the usual correction:
  ///
  /// ```dart
  /// onReorder: (int oldIndex, int newIndex) {
  ///   setState(() {
  ///     if (newIndex > oldIndex) newIndex -= 1;
  ///     items.insert(newIndex, items.removeAt(oldIndex));
  ///   });
  /// },
  /// ```
  ///
  /// Dragging works the whole length of the list, across the anchor
  /// included. When a move steps over the anchor the list corrects the anchor
  /// itself, so the viewport does not slide by a row underneath you.
  ///
  /// Every item must carry a [Key], or the framework cannot follow an item to
  /// its new index. Reordering also needs an [Overlay] above the list, which
  /// [WidgetsApp] and [MaterialApp] both provide.
  final ReorderCallback? onReorder;

  /// Called with the item's index when a drag starts.
  final void Function(int index)? onReorderStart;

  /// Called with the index the item is dropped at when a drag ends.
  ///
  /// This runs before [onReorder] and, like it, counts with the dragged item
  /// still in place.
  final void Function(int index)? onReorderEnd;

  /// Decorates the floating copy of the item while it is being dragged.
  ///
  /// The animation runs forward as the drag begins and back as it settles, so
  /// an elevation or a scale can be driven straight off it. Without one the
  /// item is drawn exactly as it sits in the list.
  final ReorderItemProxyDecorator? proxyDecorator;

  /// Whether a long press anywhere on an item starts dragging it.
  ///
  /// True by default, which is what you want on touch: an immediate drag
  /// would fight the scroll gesture. Set it false to put the gesture
  /// somewhere deliberate instead — wrap a handle inside the item in an
  /// [AnchoredListDragStartListener] and only that handle will drag.
  ///
  /// Ignored when [onReorder] is null.
  final bool longPressToDrag;

  /// How fast the list scrolls when a drag reaches its edge.
  final double autoScrollerVelocityScalar;

  /// The reordering half of the nearest enclosing [AnchoredList].
  ///
  /// Throws when there is no list above [context]; use [maybeOf] where that
  /// is a possibility.
  static AnchoredListReorder of(BuildContext context) {
    final AnchoredListReorder? found = maybeOf(context);
    if (found == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('AnchoredList.of() called with a context that has no '
            'AnchoredList above it.'),
        context.describeElement('The context used was'),
      ]);
    }
    return found;
  }

  /// The reordering half of the nearest enclosing [AnchoredList], or null.
  static AnchoredListReorder? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<_AnchoredListState>()?._reorder;

  @override
  State<AnchoredList> createState() => _AnchoredListState();
}

class _AnchoredListState extends State<AnchoredList>
    with TickerProviderStateMixin
    implements AnchoredListBinding, _ReorderHost {
  /// Marks the sliver that owns scroll offset zero.
  final Key _centreKey = UniqueKey();

  /// Only set when the caller did not supply one, and only this one is ours
  /// to dispose.
  ScrollController? _ownedScroll;

  /// Items currently built, by list index, across both slivers.
  ///
  /// Kept so movement can hand a real element to [Scrollable.ensureVisible]
  /// rather than reimplementing offset arithmetic over sliver internals — and
  /// so reordering has one registry spanning the anchor, which is the whole
  /// reason a drag can cross it. See [_ReorderController].
  final Map<int, _RegisteredItemState> _built = <int, _RegisteredItemState>{};

  late final _ReorderController _reorder = _ReorderController(this);

  bool get _reorderable => widget.onReorder != null;

  late int _anchorIndex = _clamp(widget.initialIndex);
  late double _alignment = widget.initialAlignment;
  bool _positionsScheduled = false;

  @override
  ScrollController get scrollController =>
      widget.scrollController ?? _ownedScroll!;

  int _clamp(int index) =>
      widget.itemCount == 0 ? 0 : index.clamp(0, widget.itemCount - 1);

  @override
  Map<int, _RegisteredItemState> get builtItems => _built;

  @override
  AnchoredList get config => widget;

  @override
  BuildContext get hostContext => context;

  @override
  TickerProvider get vsync => this;

  @override
  AxisDirection get axisDirection => _axisDirection;

  @override
  void reorderSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// The anchor to build against.
  ///
  /// [_anchorIndex] is deliberately stored unclamped. `shiftAnchor` runs
  /// between the caller's `setState` and the rebuild that delivers the longer
  /// list, so `widget.itemCount` is still the old count at that moment;
  /// clamping on write would throw the shift away exactly when the anchor sits
  /// near the end. Clamping on read keeps the intent until the real count
  /// arrives, and `didUpdateWidget` settles it.
  int get _anchor => _clamp(_anchorIndex);

  @override
  int get anchorIndex => _anchor;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
    if (widget.scrollController == null) _ownedScroll = ScrollController();
    scrollController.addListener(_schedulePositions);
  }

  @override
  void didUpdateWidget(AnchoredList old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.detach(this);
      widget.controller?.attach(this);
    }
    if (old.scrollController != widget.scrollController) {
      (old.scrollController ?? _ownedScroll)?.removeListener(
        _schedulePositions,
      );
      if (widget.scrollController == null) {
        _ownedScroll ??= ScrollController();
      } else {
        _ownedScroll?.dispose();
        _ownedScroll = null;
      }
      scrollController.addListener(_schedulePositions);
    }
    if (widget.itemCount != old.itemCount) {
      _anchorIndex = _clamp(_anchorIndex);
    }
    _reorder.didUpdateConfig(old);
  }

  @override
  void dispose() {
    _reorder.dispose();
    widget.controller?.detach(this);
    scrollController.removeListener(_schedulePositions);
    _ownedScroll?.dispose();
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
    final ScrollController scroll = scrollController;
    if (scroll.hasClients && scroll.offset != 0) scroll.jumpTo(0);
    if (alignment != 0) _alignToBox(_clamp(index), alignment);
    _schedulePositions();
  }

  /// Turns leading-edge alignment into box alignment, once the item is laid
  /// out and its extent is known.
  ///
  /// The viewport anchor can only place the anchored item's *leading edge* at
  /// `alignment` of the viewport, so `alignment: 1` put the item wholly below
  /// the fold and `0.5` was not centred — while `animateToIndex`, which goes
  /// through `ensureVisible`, aligns the box. Two adjacent buttons with the
  /// same argument disagreed. This corrects by the item's own extent so both
  /// paths mean the same thing.
  void _alignToBox(int index, double alignment) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final _RegisteredItemState? item = _built[index];
      final RenderObject? box =
          item?.mounted ?? false ? item!.context.findRenderObject() : null;
      if (box is! RenderBox || !box.hasSize) return;
      final double extent = widget.scrollDirection == Axis.vertical
          ? box.size.height
          : box.size.width;
      final ScrollController scroll = scrollController;
      if (!scroll.hasClients || extent == 0) return;
      final ScrollPosition p = scroll.position;
      scroll.jumpTo(
        (p.pixels + alignment * extent).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void shiftAnchor(int delta) {
    if (delta == 0 || widget.itemCount == 0) return;
    // Not clamped: see [_anchor]. The count that would clamp this is one the
    // caller has inserted into but not yet rebuilt with.
    final int next = math.max(0, _anchorIndex + delta);
    if (next == _anchorIndex) return;
    setState(() => _anchorIndex = next);
    // Deliberately does not touch the scroll offset. The anchor moved by
    // exactly the number of items that moved with it, so the same content is
    // under the same pixels and nothing should shift on screen.
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
      final int staging = target > _anchor
          ? math.max(0, target - approach)
          : math.min(widget.itemCount - 1, target + approach);
      // Stage at the leading edge, not at `alignment` — see below.
      jumpToIndex(staging, 0);
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final _RegisteredItemState? item = _built[target];
    if (item == null || !item.mounted) {
      jumpToIndex(target, alignment);
      return;
    }
    // Alignment is consumed exactly once, by ensureVisible. Letting the
    // viewport anchor take it as well applied it twice: the viewport paints
    // offset zero at `extent * anchor`, and getOffsetToReveal — which
    // ensureVisible drives — never reads the anchor, so the target landed
    // about a screenful of `alignment` past where it was asked to go.
    if (_alignment != 0) {
      setState(() => _alignment = 0);
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted || !item.mounted) return;
    }
    await Scrollable.ensureVisible(
      item.context,
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
    for (final MapEntry<int, _RegisteredItemState> entry in _built.entries) {
      if (!entry.value.mounted) continue;
      final RenderObject? box = entry.value.context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;

      final Offset origin = box.localToGlobal(Offset.zero, ancestor: self);
      final double lead =
          widget.scrollDirection == Axis.vertical ? origin.dy : origin.dx;
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

  /// One delegate child: the item, registered, plus its separator if any.
  ///
  /// The item's key is lifted onto whatever is returned, so
  /// [AnchoredList.findChildIndexCallback] and Flutter's own key matching see
  /// the key the caller actually set rather than the wrapper.
  Widget _item(BuildContext context, int index) {
    final Widget child = widget.itemBuilder(context, index);

    // The child's key is lifted onto the wrapper so key-based child matching
    // still works, but it has to be salted first: copying a GlobalKey onto the
    // wrapper leaves two live elements registered under the same key and
    // Flutter throws "Multiple widgets used the same GlobalKey". This is what
    // SliverChildBuilderDelegate does with _SaltedValueKey for the same
    // reason.
    final Key? lifted = child.key == null ? null : _AnchoredKey(child.key!);

    if (!_reorderable) {
      return _withSeparator(
        context,
        index,
        _RegisteredItem(
          index: index,
          registry: _built,
          onMounted: _schedulePositions,
          child: child,
        ),
        key: lifted,
      );
    }

    assert(
      child.key != null,
      'Every item needs a Key when onReorder is set, or an item cannot be '
      'followed to its new index. Item $index has none.',
    );
    // Registering the item *and* its separator as one unit, rather than the
    // item alone, is what makes the gap the right size: the drag lifts the
    // pair, so the hole it leaves has to be the pair's extent.
    return KeyedSubtree(
      key: lifted,
      child: _RegisteredItem(
        index: index,
        registry: _built,
        onMounted: _schedulePositions,
        reorder: _reorder,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Overlay.of(context, debugRequiredFor: widget).context,
        ),
        child:
            _withSeparator(context, index, _draggable(context, index, child)),
      ),
    );
  }

  /// Pairs an item with its separator, when there is one to pair it with.
  Widget _withSeparator(
    BuildContext context,
    int index,
    Widget item, {
    Key? key,
  }) {
    final IndexedWidgetBuilder? separator = widget.separatorBuilder;
    if (separator == null || index >= widget.itemCount - 1) {
      return KeyedSubtree(key: key, child: item);
    }
    final List<Widget> pair = <Widget>[item, separator(context, index)];
    return widget.scrollDirection == Axis.vertical
        ? Column(
            key: key,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pair,
          )
        : Row(
            key: key,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: pair,
          );
  }

  /// Gives an item the gesture that starts a drag, and the screen-reader
  /// actions that move it without one.
  Widget _draggable(BuildContext context, int index, Widget child) {
    final Widget described = _reorderSemantics(context, index, child);
    return widget.longPressToDrag
        ? AnchoredListDelayedDragStartListener(index: index, child: described)
        : described;
  }

  /// The move-item actions a screen reader offers in place of dragging.
  ///
  /// Skipped rather than thrown when there are no [WidgetsLocalizations]
  /// above the list — a bare widget test is not a reason to fail to build.
  Widget _reorderSemantics(BuildContext context, int index, Widget child) {
    final WidgetsLocalizations? l10n =
        Localizations.of<WidgetsLocalizations>(context, WidgetsLocalizations);
    if (l10n == null) return child;

    final Map<CustomSemanticsAction, VoidCallback> actions =
        <CustomSemanticsAction, VoidCallback>{};
    final bool horizontal = widget.scrollDirection == Axis.horizontal;
    final bool ltr = Directionality.of(context) == TextDirection.ltr;

    if (index > 0) {
      actions[CustomSemanticsAction(label: l10n.reorderItemToStart)] =
          () => _reorder.handleReorder(index, 0);
      final String before = !horizontal
          ? l10n.reorderItemUp
          : (ltr ? l10n.reorderItemLeft : l10n.reorderItemRight);
      actions[CustomSemanticsAction(label: before)] =
          () => _reorder.handleReorder(index, index - 1);
    }
    if (index < widget.itemCount - 1) {
      final String after = !horizontal
          ? l10n.reorderItemDown
          : (ltr ? l10n.reorderItemRight : l10n.reorderItemLeft);
      // index + 2, because the item lands *before* that index and it is still
      // counted in place.
      actions[CustomSemanticsAction(label: after)] =
          () => _reorder.handleReorder(index, index + 2);
      actions[CustomSemanticsAction(label: l10n.reorderItemToEnd)] =
          () => _reorder.handleReorder(index, widget.itemCount);
    }
    return Semantics(
      container: true,
      customSemanticsActions: actions,
      child: child,
    );
  }

  /// Translates a caller's list index into an index within one sliver.
  ///
  /// The caller thinks in list indices; each delegate counts from its own
  /// start, and the leading one counts *backwards*.
  ChildIndexGetter? _findChildIndex({
    required bool leading,
    required int childCount,
  }) {
    final ChildIndexGetter? find = widget.findChildIndexCallback;
    if (find == null) return null;
    return (Key key) {
      // Unwrap the salt applied in _item before handing the key back to the
      // caller, who only ever saw their own.
      final Key unsalted = key is _AnchoredKey ? key.value : key;
      final int? listIndex = find(unsalted);
      if (listIndex == null) return null;
      final int local = leading ? _anchor - 1 - listIndex : listIndex - _anchor;
      return local >= 0 && local < childCount ? local : null;
    };
  }

  @override
  Widget build(BuildContext context) {
    final int leading = _anchor;
    final int trailing = math.max(0, widget.itemCount - _anchor);

    return CustomScrollView(
      controller: scrollController,
      // Offset zero lives here: the sliver that starts at the anchor.
      center: _centreKey,
      anchor: _alignment,
      scrollDirection: widget.scrollDirection,
      reverse: widget.reverse,
      physics: widget.physics,
      // Renamed to scrollCacheExtent after Flutter 3.41, but our floor is
      // 3.32 and the old name still works everywhere. Switching would drop
      // every user below 3.41 to buy nothing.
      // ignore: deprecated_member_use
      cacheExtent: widget.cacheExtent,
      semanticChildCount: widget.semanticChildCount ?? widget.itemCount,
      dragStartBehavior: widget.dragStartBehavior,
      keyboardDismissBehavior: widget.keyboardDismissBehavior,
      scrollBehavior: widget.scrollBehavior,
      clipBehavior: widget.clipBehavior,
      restorationId: widget.restorationId,
      slivers: <Widget>[
        // Everything before the anchor, built backwards into negative offset.
        SliverPadding(
          padding: _leadingPadding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext c, int i) => _item(c, _anchor - 1 - i),
              childCount: leading,
              findChildIndexCallback: _findChildIndex(
                leading: true,
                childCount: leading,
              ),
              // This sliver counts backwards, so without a translation the
              // semantics tree would announce its indices in reverse.
              semanticIndexCallback: (Widget _, int i) => _anchor - 1 - i,
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
              (BuildContext c, int i) => _item(c, _anchor + i),
              childCount: trailing,
              findChildIndexCallback: _findChildIndex(
                leading: false,
                childCount: trailing,
              ),
              semanticIndexCallback: (Widget _, int i) => _anchor + i,
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
  /// The physical side each sliver turns towards the anchor.
  ///
  /// The two slivers meet at the anchor, so the inset has to be dropped on the
  /// facing edge of each or it is applied twice in the middle and not at all
  /// at the ends. Which physical edge that is depends on the *resolved* axis
  /// direction, not just the scroll axis — under `reverse: true` (a chat) or
  /// RTL the leading sliver grows the other way, and splitting by axis alone
  /// put the whole inset in a gap at the anchor.
  AxisDirection get _axisDirection =>
      getAxisDirectionFromAxisReverseAndDirectionality(
        context,
        widget.scrollDirection,
        widget.reverse,
      );

  EdgeInsets get _leadingPadding => switch (_axisDirection) {
        AxisDirection.down => _padding.copyWith(bottom: 0),
        AxisDirection.up => _padding.copyWith(top: 0),
        AxisDirection.right => _padding.copyWith(right: 0),
        AxisDirection.left => _padding.copyWith(left: 0),
      };

  EdgeInsets get _trailingPadding => switch (_axisDirection) {
        AxisDirection.down => _padding.copyWith(top: 0),
        AxisDirection.up => _padding.copyWith(bottom: 0),
        AxisDirection.right => _padding.copyWith(left: 0),
        AxisDirection.left => _padding.copyWith(right: 0),
      };

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
    required this.child,
    this.reorder,
    this.capturedThemes,
  });

  final int index;
  final Map<int, _RegisteredItemState> registry;
  final VoidCallback onMounted;
  final Widget child;

  /// Set only when the list is reorderable, and then the same controller for
  /// every item.
  final _ReorderController? reorder;

  /// The inherited widgets the item needs carried with it into the overlay
  /// while it is being dragged.
  final CapturedThemes? capturedThemes;

  @override
  State<_RegisteredItem> createState() => _RegisteredItemState();
}

class _RegisteredItemState extends State<_RegisteredItem> {
  Offset _startOffset = Offset.zero;
  Offset _targetOffset = Offset.zero;
  AnimationController? _gap;
  bool _dragging = false;

  int get index => widget.index;

  CapturedThemes get capturedThemes => widget.capturedThemes!;

  /// Whether this item is the one in the air, in which case it holds its
  /// place open and the overlay draws it instead.
  bool get dragging => _dragging;
  set dragging(bool value) {
    if (_dragging == value) return;
    _dragging = value;
    rebuild();
  }

  @override
  void initState() {
    super.initState();
    widget.registry[widget.index] = this;
    widget.reorder?.registerItem(this);
    widget.onMounted();
  }

  @override
  void didUpdateWidget(_RegisteredItem old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (widget.registry[old.index] == this) {
        widget.registry.remove(old.index);
      }
      widget.registry[widget.index] = this;
      widget.reorder?.registerItem(this);
    }
  }

  @override
  void dispose() {
    _gap?.dispose();
    _gap = null;
    if (widget.registry[widget.index] == this) {
      widget.registry.remove(widget.index);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _ReorderController? reorder = widget.reorder;
    if (reorder == null) return widget.child;
    if (_dragging) {
      // Hold the space open at exactly the extent that left, so nothing below
      // jumps while the item is in the air.
      return SizedBox.fromSize(
        size: _extentSize(reorder.draggedExtent ?? 0, reorder.axis),
      );
    }
    widget.registry[widget.index] = this;
    return Transform.translate(offset: offset, child: widget.child);
  }

  /// How far this item is currently shifted to make room for the gap.
  Offset get offset {
    final AnimationController? gap = _gap;
    if (gap == null) return _targetOffset;
    return Offset.lerp(
      _startOffset,
      _targetOffset,
      Curves.easeInOut.transform(gap.value),
    )!;
  }

  /// Where this item will be once the gap animation settles.
  ///
  /// The target rather than the painted position, so a drop index computed
  /// mid-animation is the one the eye is already being shown.
  Rect targetGeometry() {
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return Rect.zero;
    return (object.localToGlobal(Offset.zero) + _targetOffset) & object.size;
  }

  /// Opens or closes this item's share of the gap left by the dragged item.
  ///
  /// Everything between the dragged item and where it would land shifts by
  /// one item's extent; everything else sits still.
  void updateForGap(
    int dragIndex,
    int gapIndex,
    double gapExtent, {
    required bool animate,
    required bool reverse,
  }) {
    final Axis axis = widget.reorder!.axis;
    final Offset wanted;
    if (gapIndex < dragIndex && index < dragIndex && index >= gapIndex) {
      wanted = _extentOffset(reverse ? -gapExtent : gapExtent, axis);
    } else if (gapIndex > dragIndex && index > dragIndex && index < gapIndex) {
      wanted = _extentOffset(reverse ? gapExtent : -gapExtent, axis);
    } else {
      wanted = Offset.zero;
    }
    if (wanted == _targetOffset) return;

    final Offset previous = _targetOffset;
    _targetOffset = wanted;
    if (!animate) {
      _gap?.dispose();
      _gap = null;
      _startOffset = _targetOffset;
      rebuild();
      return;
    }
    final AnimationController? running = _gap;
    if (running == null) {
      _gap = AnimationController(
        vsync: widget.reorder!.vsync,
        duration: const Duration(milliseconds: 250),
      )
        ..addListener(rebuild)
        ..addStatusListener((AnimationStatus status) {
          if (!status.isCompleted) return;
          _startOffset = _targetOffset;
          _gap?.dispose();
          _gap = null;
        })
        ..forward();
    } else {
      // Interrupted mid-slide: carry on from where it actually is, not from
      // where the last animation started.
      _startOffset = Offset.lerp(
        _startOffset,
        previous,
        Curves.easeInOut.transform(running.value),
      )!;
      running.forward(from: 0);
    }
    rebuild();
  }

  /// Puts the item back where it belongs once the drag is over.
  void resetGap() {
    _gap?.dispose();
    _gap = null;
    _startOffset = Offset.zero;
    _targetOffset = Offset.zero;
    rebuild();
  }

  void rebuild() {
    if (mounted) setState(() {});
  }
}

/// Wraps a caller's item key so it can be lifted onto the wrapper widget
/// without two elements registering the same [GlobalKey].
///
/// The framework does the same thing with `_SaltedValueKey` inside
/// `SliverChildBuilderDelegate`.
class _AnchoredKey extends ValueKey<Key> {
  const _AnchoredKey(super.value);
}
