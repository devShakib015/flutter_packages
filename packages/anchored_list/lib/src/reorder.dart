part of 'anchored_list.dart';

/// How an [AnchoredList] starts a drag, as the drag listeners see it.
///
/// Obtained with [AnchoredList.of] or [AnchoredList.maybeOf]. Most callers
/// never touch this: wrapping an item, or a handle inside it, in an
/// [AnchoredListDragStartListener] is enough.
abstract class AnchoredListReorder {
  /// Begins dragging the item at [index], following the pointer-down [event].
  ///
  /// [recognizer] decides what gesture starts the drag — an
  /// [ImmediateMultiDragGestureRecognizer] for a handle, a
  /// [DelayedMultiDragGestureRecognizer] for a long press.
  ///
  /// The item must be built. Dragging one that is scrolled out of view has no
  /// meaning, since the pointer is by definition over something else.
  void startItemDragReorder({
    required int index,
    required PointerDownEvent event,
    required MultiDragGestureRecognizer recognizer,
  });

  /// Abandons a drag in progress and puts every item back where it was.
  ///
  /// Call this before changing the list out from under a drag. The list does
  /// it for you when `itemCount` changes.
  void cancelReorder();
}

/// Starts a drag as soon as a pointer goes down on [child].
///
/// Wrap a drag handle in this — a grip icon, a corner of the row — when the
/// item itself has to stay tappable or scrollable:
///
/// ```dart
/// AnchoredList.builder(
///   itemCount: items.length,
///   onReorder: _move,
///   longPressToDrag: false,
///   itemBuilder: (context, index) => Row(
///     key: ValueKey(items[index].id),
///     children: <Widget>[
///       Expanded(child: Text(items[index].title)),
///       AnchoredListDragStartListener(
///         index: index,
///         child: const Icon(Icons.drag_handle),
///       ),
///     ],
///   ),
/// )
/// ```
///
/// See also:
///
///  * [AnchoredListDelayedDragStartListener], which waits for a long press.
class AnchoredListDragStartListener extends StatelessWidget {
  /// Creates a listener that drags [index] the moment a pointer goes down.
  const AnchoredListDragStartListener({
    required this.child,
    required this.index,
    super.key,
    this.enabled = true,
  });

  /// The handle, or the whole item, that starts the drag.
  final Widget child;

  /// The index of the item this drags.
  final int index;

  /// Whether the drag can start at all.
  final bool enabled;

  /// The recognizer that decides when the drag begins.
  ///
  /// Override it in a subclass to change the gesture;
  /// [AnchoredListDelayedDragStartListener] does exactly that.
  @protected
  MultiDragGestureRecognizer createRecognizer() =>
      ImmediateMultiDragGestureRecognizer(debugOwner: this);

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown:
            enabled ? (PointerDownEvent e) => _start(context, e) : null,
        child: child,
      );

  void _start(BuildContext context, PointerDownEvent event) {
    final DeviceGestureSettings? settings =
        MediaQuery.maybeGestureSettingsOf(context);
    AnchoredList.maybeOf(context)?.startItemDragReorder(
      index: index,
      event: event,
      recognizer: createRecognizer()..gestureSettings = settings,
    );
  }
}

/// Starts a drag after a long press on [child].
///
/// This is what `longPressToDrag: true` wraps every item in, and the right
/// choice on touch, where an immediate drag would fight the scroll gesture.
class AnchoredListDelayedDragStartListener
    extends AnchoredListDragStartListener {
  /// Creates a listener that drags [index] after a long press.
  const AnchoredListDelayedDragStartListener({
    required super.child,
    required super.index,
    super.key,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(debugOwner: this);
}

// ------------------------------------------------------------------- host

/// What the reorder controller needs from the list it belongs to.
///
/// Implemented by `_AnchoredListState`. Split out so the drag machinery can
/// live in one file and be reasoned about without the viewport around it.
abstract class _ReorderHost {
  /// Every item currently built, by list index, across *both* slivers.
  Map<int, _RegisteredItemState> get builtItems;

  /// The list's current configuration.
  AnchoredList get config;

  /// The list's own element, used for the overlay and for localisation.
  BuildContext get hostContext;

  /// Drives the gap and proxy animations.
  TickerProvider get vsync;

  /// The resolved axis direction, which already accounts for `reverse` and
  /// the ambient [Directionality].
  AxisDirection get axisDirection;

  /// Rebuilds the list.
  void reorderSetState(VoidCallback fn);

  /// Moves the anchor by [delta] without touching the scroll offset.
  void shiftAnchor(int delta);

  /// The index currently at scroll offset zero.
  int get anchorIndex;
}

// ------------------------------------------------------------- controller

/// The whole of reordering: which item is in the air, where it would land,
/// and the gap the rest of the list opens for it.
///
/// This is a re-implementation rather than a use of `SliverReorderableList`,
/// and it has to be. That widget finds its drop index by walking only the
/// children registered with itself, and an [AnchoredList] is two slivers —
/// items before the anchor in one, the anchor and everything after in the
/// other. Two reorderable slivers would be two separate reorder domains, and
/// a drag across the anchor would find no target and open no gap.
///
/// Working from [_ReorderHost.builtItems] instead costs nothing and fixes
/// that outright: the registry is keyed by *list* index and does not know or
/// care which sliver an item is in. Auto-scrolling across the anchor is a
/// non-event for the same reason — the two slivers share one scroll space, so
/// crossing the anchor is just passing through offset zero.
class _ReorderController implements AnchoredListReorder {
  _ReorderController(this._host);

  final _ReorderHost _host;

  OverlayEntry? _overlayEntry;
  int? _dragIndex;
  _DragInfo? _dragInfo;
  int? _insertIndex;
  MultiDragGestureRecognizer? _recognizer;
  int? _recognizerPointer;
  EdgeDraggingAutoScroller? _autoScroller;

  Axis get _axis => axisDirectionToAxis(_host.axisDirection);
  bool get _reverse => axisDirectionIsReversed(_host.axisDirection);

  /// The axis items shift along to open a gap.
  Axis get axis => _axis;

  /// Drives the gap animations.
  TickerProvider get vsync => _host.vsync;

  /// The extent the item in the air left behind, or null when nothing is
  /// being dragged.
  double? get draggedExtent => _dragInfo?.itemExtent;
  Map<int, _RegisteredItemState> get _items => _host.builtItems;
  int get _itemCount => _host.config.itemCount;

  void dispose() {
    _dragReset();
    _recognizer?.dispose();
    _recognizer = null;
  }

  /// Called when the list's configuration changes.
  void didUpdateConfig(AnchoredList old) {
    if (old.itemCount != _host.config.itemCount) cancelReorder();
    if (old.autoScrollerVelocityScalar !=
        _host.config.autoScrollerVelocityScalar) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = null;
    }
  }

  // -------------------------------------------------------------- registry

  void registerItem(_RegisteredItemState item) {
    if (_dragInfo != null && _items[item.index] != item) {
      item.updateForGap(
        _dragInfo!.index,
        _insertIndex ?? _dragInfo!.index,
        _dragInfo!.itemExtent,
        animate: false,
        reverse: _reverse,
      );
    }
    if (item.index == _dragIndex) item.dragging = true;
  }

  // ----------------------------------------------------------- drag start

  @override
  void startItemDragReorder({
    required int index,
    required PointerDownEvent event,
    required MultiDragGestureRecognizer recognizer,
  }) {
    assert(index >= 0 && index < _itemCount, 'index is outside the list');
    _host.reorderSetState(() {
      if (_dragInfo != null) {
        cancelReorder();
      } else if (_recognizer != null && _recognizerPointer != event.pointer) {
        _recognizer!.dispose();
        _recognizer = null;
        _recognizerPointer = null;
      }
      if (!_items.containsKey(index)) {
        // Nothing sensible to drag: the pointer is over something else.
        recognizer.dispose();
        return;
      }
      _dragIndex = index;
      _recognizer = recognizer
        ..onStart = _dragStart
        ..addPointer(event);
      _recognizerPointer = event.pointer;
    });
  }

  @override
  void cancelReorder() => _host.reorderSetState(_dragReset);

  Drag? _dragStart(Offset position) {
    assert(_dragInfo == null, 'a drag is already in flight');
    final _RegisteredItemState? item = _items[_dragIndex];
    if (item == null || !item.mounted) return null;

    item.dragging = true;
    _host.config.onReorderStart?.call(_dragIndex!);
    item.rebuild();

    final ScrollableState? scrollable = Scrollable.maybeOf(item.context);
    if (scrollable != null && _autoScroller?.scrollable != scrollable) {
      _autoScroller?.stopAutoScroll();
      _autoScroller = EdgeDraggingAutoScroller(
        scrollable,
        onScrollViewScrolled: _handleAutoScrolled,
        velocityScalar: _host.config.autoScrollerVelocityScalar,
      );
    }

    _insertIndex = item.index;
    _dragInfo = _DragInfo(
      item: item,
      axis: _axis,
      initialPosition: position,
      proxyDecorator: _host.config.proxyDecorator,
      vsync: _host.vsync,
      onUpdate: _dragUpdate,
      onCancel: _dragCancel,
      onEnd: _dragEnd,
      onDropCompleted: _dropCompleted,
    )..startDrag();

    final OverlayState overlay =
        Overlay.of(_host.hostContext, debugRequiredFor: _host.config);
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = OverlayEntry(builder: _dragInfo!.buildProxy);
    overlay.insert(_overlayEntry!);

    for (final _RegisteredItemState other in _items.values) {
      if (other == item || !other.mounted) continue;
      other.updateForGap(
        _insertIndex!,
        _insertIndex!,
        _dragInfo!.itemExtent,
        animate: false,
        reverse: _reverse,
      );
    }
    return _dragInfo;
  }

  // ---------------------------------------------------------- drag update

  void _dragUpdate(_DragInfo item, Offset position, Offset delta) {
    _host.reorderSetState(() {
      _overlayEntry?.markNeedsBuild();
      _updateItems();
      _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect);
    });
  }

  void _handleAutoScrolled() {
    if (_dragInfo == null) return;
    _updateItems();
    _autoScroller?.startAutoScrollIfNecessary(_dragTargetRect);
  }

  /// Decides where the dragged item would land, and opens the gap for it.
  ///
  /// Straight from the framework's own algorithm, with one difference that is
  /// the entire point of this class: the items it walks are every built item
  /// in the list, on both sides of the anchor, not the children of one sliver.
  void _updateItems() {
    final _DragInfo drag = _dragInfo!;
    final double gap = drag.itemExtent;
    final double proxyStart =
        _offsetExtent(drag.dragPosition - drag.dragOffset, _axis);
    final double proxyEnd = proxyStart + gap;

    int newIndex = _insertIndex!;
    for (final _RegisteredItemState item in _items.values) {
      if (!item.mounted) continue;
      if (_reverse && item.index == _dragIndex) continue;

      final Rect box = item.targetGeometry();
      // Built but not yet laid out: it has no position to compare against,
      // and treating it as a zero-extent item at the origin would drag the
      // drop index to the top of the list.
      if (box == Rect.zero) continue;
      final double start = _axis == Axis.vertical ? box.top : box.left;
      final double extent = _axis == Axis.vertical ? box.height : box.width;
      final double end = start + extent;
      final double middle = start + extent / 2;

      if (_reverse) {
        if (end >= proxyEnd && proxyEnd >= middle) {
          newIndex = item.index;
          break;
        } else if (middle >= proxyStart && proxyStart >= start) {
          newIndex = item.index + 1;
          break;
        } else if (start > proxyEnd && newIndex < item.index + 1) {
          newIndex = item.index + 1;
        } else if (proxyStart > end && newIndex > item.index) {
          newIndex = item.index;
        }
      } else {
        if (item.index == _dragIndex) {
          if (middle <= proxyEnd && proxyEnd <= end) newIndex = _dragIndex!;
        } else if (start <= proxyStart && proxyStart <= middle) {
          newIndex = item.index;
          break;
        } else if (middle <= proxyEnd && proxyEnd <= end) {
          newIndex = item.index + 1;
          break;
        } else if (end < proxyStart && newIndex < item.index + 1) {
          newIndex = item.index + 1;
        } else if (proxyEnd < start && newIndex > item.index) {
          newIndex = item.index;
        }
      }
    }

    if (newIndex == _insertIndex) return;
    _insertIndex = newIndex;
    for (final _RegisteredItemState item in _items.values) {
      if (item.index == _dragIndex || !item.mounted) continue;
      item.updateForGap(
        _dragIndex!,
        newIndex,
        gap,
        animate: true,
        reverse: _reverse,
      );
    }
  }

  Rect get _dragTargetRect {
    final _DragInfo drag = _dragInfo!;
    final Offset origin = drag.dragPosition - drag.dragOffset;
    return Rect.fromLTWH(
      origin.dx,
      origin.dy,
      drag.itemSize.width,
      drag.itemSize.height,
    );
  }

  // ------------------------------------------------------------- drag end

  void _dragCancel(_DragInfo item) => _host.reorderSetState(_dragReset);

  void _dragEnd(_DragInfo item) {
    final int? insert = _insertIndex;
    if (insert == null) return;
    _host.reorderSetState(
        () => item.landingPosition = _restingPlace(item, insert));
    _host.config.onReorderEnd?.call(insert);
  }

  /// Where the proxy settles, so the drop reads as the item taking its seat
  /// rather than vanishing.
  ///
  /// Null whenever the seat is not built — dropping onto a target that has
  /// scrolled away is possible here, and then the proxy simply fades out
  /// where it is instead of flying somewhere arbitrary.
  Offset? _restingPlace(_DragInfo item, int insert) {
    if (insert - item.index == 1) {
      // Back where it started, approached from below: the insert index is one
      // past the item because it is computed with the item still in place.
      return _offsetAt(insert - 1);
    }
    if (insert == item.index) return _offsetAt(insert);

    if (_reverse) {
      if (insert >= _itemCount) {
        final Offset? last = _offsetAt(_itemCount - 1);
        return last == null
            ? null
            : last - _extentOffset(item.itemExtent, _axis);
      }
      final Offset? at = _offsetAt(insert);
      final double? extent = _extentAt(insert);
      return at == null || extent == null
          ? null
          : at + _extentOffset(extent, _axis);
    }
    if (insert == 0) {
      final Offset? first = _offsetAt(0);
      return first == null
          ? null
          : first - _extentOffset(item.itemExtent, _axis);
    }
    final int above = insert - 1;
    final Offset? at = _offsetAt(above);
    final double? extent = _extentAt(above);
    return at == null || extent == null
        ? null
        : at + _extentOffset(extent, _axis);
  }

  void _dropCompleted() {
    final int? oldIndex = _dragIndex;
    final int? newIndex = _insertIndex;
    _host.reorderSetState(_dragReset);
    if (oldIndex != null && newIndex != null) handleReorder(oldIndex, newIndex);
  }

  /// Hands the move to the caller and then keeps the viewport still.
  ///
  /// A reorder that steps over the anchor changes how many items sit above
  /// it, which would slide everything on screen by one row. The anchor is an
  /// index, so the correction is the same single increment
  /// [AnchoredListController.itemsInsertedAbove] makes.
  void handleReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _host.config.onReorder?.call(oldIndex, newIndex);

    // `newIndex` counts with the item still in place, so it is one too high
    // for any move down the list.
    final int landed = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final int anchor = _host.anchorIndex;
    if (oldIndex < anchor && landed >= anchor) {
      _host.shiftAnchor(-1);
    } else if (oldIndex >= anchor && landed < anchor) {
      _host.shiftAnchor(1);
    }
  }

  void _dragReset() {
    if (_dragInfo == null) return;
    final _RegisteredItemState? dragged = _items[_dragIndex];
    if (dragged != null) {
      dragged.dragging = false;
      dragged.rebuild();
    }
    _dragIndex = null;
    _insertIndex = null;
    _dragInfo?.dispose();
    _dragInfo = null;
    _autoScroller?.stopAutoScroll();
    for (final _RegisteredItemState item in _items.values) {
      item.resetGap();
    }
    _recognizer?.dispose();
    _recognizer = null;
    _recognizerPointer = null;
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  Offset? _offsetAt(int index) {
    final Rect? box = _items[index]?.targetGeometry();
    return box == null || box == Rect.zero ? null : box.topLeft;
  }

  double? _extentAt(int index) {
    final Rect? box = _items[index]?.targetGeometry();
    return box == null || box == Rect.zero
        ? null
        : _sizeExtent(box.size, _axis);
  }
}

// ---------------------------------------------------------------- the drag

/// The item in the air: where the pointer is, how big the thing is, and the
/// animation that carries it to its seat on release.
class _DragInfo extends Drag {
  _DragInfo({
    required _RegisteredItemState item,
    required this.axis,
    required this.vsync,
    required Offset initialPosition,
    this.proxyDecorator,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    this.onDropCompleted,
  }) {
    final RenderBox box = item.context.findRenderObject()! as RenderBox;
    index = item.index;
    child = item.widget.child;
    capturedThemes = item.capturedThemes;
    dragOffset = box.globalToLocal(initialPosition);
    itemSize = item.context.size!;
    itemConstraints = box.constraints;
    dragPosition = initialPosition;
    itemExtent = _sizeExtent(itemSize, axis);
  }

  final Axis axis;
  final TickerProvider vsync;
  final ReorderItemProxyDecorator? proxyDecorator;
  final void Function(_DragInfo item, Offset position, Offset delta)? onUpdate;
  final void Function(_DragInfo item)? onEnd;
  final void Function(_DragInfo item)? onCancel;
  final VoidCallback? onDropCompleted;

  late final int index;
  late final Widget child;
  late final CapturedThemes capturedThemes;
  late final Offset dragOffset;
  late final Size itemSize;
  late final BoxConstraints itemConstraints;
  late final double itemExtent;
  late Offset dragPosition;

  /// Where the proxy flies to once the pointer lets go, or null to fade out
  /// where it is because the seat it was aiming for is no longer built.
  Offset? landingPosition;

  AnimationController? _proxy;

  /// The proxy's own animation: forward while dragging, reversed on release,
  /// and the drop is committed when it reaches zero.
  Animation<double> get animation => _proxy!.view;

  void startDrag() {
    _proxy = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 250),
    )
      ..addStatusListener((AnimationStatus status) {
        if (status.isDismissed) {
          _proxy?.dispose();
          _proxy = null;
          onDropCompleted?.call();
        }
      })
      ..forward();
  }

  @override
  void update(DragUpdateDetails details) {
    dragPosition += _restrictAxis(details.delta, axis);
    onUpdate?.call(this, dragPosition, details.delta);
  }

  @override
  void end(DragEndDetails details) {
    // Order matters. A drag released in the frame it began reverses from
    // zero, which completes synchronously and commits the drop there and
    // then — so the resting place has to be known first.
    onEnd?.call(this);
    _proxy?.reverse();
  }

  @override
  void cancel() {
    _proxy?.dispose();
    _proxy = null;
    onCancel?.call(this);
  }

  void dispose() {
    _proxy?.dispose();
    _proxy = null;
  }

  Widget buildProxy(BuildContext context) => capturedThemes.wrap(
        _DragItemProxy(
          drag: this,
          position: dragPosition - dragOffset - _overlayOrigin(context),
          child: child,
        ),
      );
}

/// The floating copy of the dragged item, painted in the overlay.
class _DragItemProxy extends StatelessWidget {
  const _DragItemProxy({
    required this.drag,
    required this.position,
    required this.child,
  });

  final _DragInfo drag;
  final Offset position;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Widget decorated =
        drag.proxyDecorator?.call(child, drag.index, drag.animation) ?? child;
    final Offset origin = _overlayOrigin(context);

    return MediaQuery(
      // A nested list inside the item would otherwise pick up the enclosing
      // scaffold's padding once it is reparented into the overlay.
      data: MediaQuery.of(context).removePadding(removeTop: true),
      child: AnimatedBuilder(
        animation: drag.animation,
        builder: (BuildContext context, Widget? proxy) {
          Offset at = position;
          final Offset? landing = drag.landingPosition;
          if (landing != null) {
            at = Offset.lerp(
              landing - origin,
              at,
              Curves.easeOut.transform(drag.animation.value),
            )!;
          }
          return Positioned(
            left: at.dx,
            top: at.dy,
            child: SizedBox(
              width: drag.itemSize.width,
              height: drag.itemSize.height,
              child: OverflowBox(
                minWidth: drag.itemConstraints.minWidth,
                minHeight: drag.itemConstraints.minHeight,
                maxWidth: drag.itemConstraints.maxWidth,
                maxHeight: drag.itemConstraints.maxHeight,
                alignment: drag.axis == Axis.horizontal
                    ? Alignment.centerLeft
                    : Alignment.topCenter,
                child: proxy,
              ),
            ),
          );
        },
        child: decorated,
      ),
    );
  }
}

Offset _overlayOrigin(BuildContext context) {
  final OverlayState overlay =
      Overlay.of(context, debugRequiredFor: context.widget);
  return (overlay.context.findRenderObject()! as RenderBox)
      .localToGlobal(Offset.zero);
}

double _sizeExtent(Size size, Axis axis) => switch (axis) {
      Axis.horizontal => size.width,
      Axis.vertical => size.height,
    };

Size _extentSize(double extent, Axis axis) => switch (axis) {
      Axis.horizontal => Size(extent, 0),
      Axis.vertical => Size(0, extent),
    };

double _offsetExtent(Offset offset, Axis axis) => switch (axis) {
      Axis.horizontal => offset.dx,
      Axis.vertical => offset.dy,
    };

Offset _extentOffset(double extent, Axis axis) => switch (axis) {
      Axis.horizontal => Offset(extent, 0),
      Axis.vertical => Offset(0, extent),
    };

Offset _restrictAxis(Offset offset, Axis axis) => switch (axis) {
      Axis.horizontal => Offset(offset.dx, 0),
      Axis.vertical => Offset(0, offset.dy),
    };
