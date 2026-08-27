import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'item_position.dart';

/// Drives an [AnchoredList] and reports what it is showing.
///
/// Attach one to a list and keep it in state:
///
/// ```dart
/// final controller = AnchoredListController();
/// ...
/// controller.jumpToIndex(842);
/// ```
class AnchoredListController extends ChangeNotifier {
  AnchoredListBinding? _binding;

  /// Whether a list is currently attached.
  bool get isAttached => _binding != null;

  /// Items currently laid out, including those in the cache area.
  ///
  /// Updated every frame the list scrolls. Use it to drive a scrollbar label,
  /// a section header, or lazy loading at the edges.
  ValueListenable<List<ItemPosition>> get itemPositions => _positions;
  final ValueNotifier<List<ItemPosition>> _positions =
      ValueNotifier<List<ItemPosition>>(const <ItemPosition>[]);

  /// The [ScrollController] driving the underlying viewport.
  ///
  /// Use it for everything index-based movement does not cover: attaching a
  /// [Scrollbar], nudging by a screenful for page-up/page-down, reading
  /// [ScrollController.position], or linking two lists together.
  ///
  /// ```dart
  /// // Page down by one viewport.
  /// final position = controller.scrollController.position;
  /// controller.scrollController.animateTo(
  ///   position.pixels + position.viewportDimension,
  ///   duration: const Duration(milliseconds: 250),
  ///   curve: Curves.easeOut,
  /// );
  /// ```
  ///
  /// **Offsets are measured from the anchor, not from the start of the list.**
  /// Zero is the anchored item and content above it sits at *negative* offset,
  /// because that is what makes a jump constant time. So
  /// `scrollController.offset == 0` means "the anchor is at the leading edge",
  /// not "the top of the list", and [ScrollPosition.minScrollExtent] is
  /// negative whenever the anchor is not item 0. Estimated extents for unbuilt
  /// items behave the same way they do in [ListView.builder].
  ///
  /// To supply your own controller instead, pass it to
  /// `AnchoredList(scrollController: ...)`; this returns whichever one the
  /// list is actually using.
  ScrollController get scrollController => _requireBinding().scrollController;

  /// Moves to [index] immediately.
  ///
  /// Constant time whatever the index and whatever the item heights — the list
  /// re-anchors rather than measuring its way there, so jumping to item
  /// 900,000 costs the same as jumping to item 3.
  ///
  /// [alignment] places the item within the viewport: 0 puts its leading edge
  /// at the top, 0.5 centres it, 1 puts it at the bottom.
  void jumpToIndex(int index, {double alignment = 0}) {
    assert(alignment >= 0 && alignment <= 1, 'alignment must be 0..1');
    _requireBinding().jumpToIndex(index, alignment);
  }

  /// Scrolls to [index] over [duration].
  ///
  /// When the target is already laid out this is an ordinary smooth scroll.
  /// When it is far outside the built range there is nothing to scroll
  /// *through* — the extent of unbuilt items is unknown — so the list
  /// re-anchors near the target and animates the final stretch. The result
  /// reads as a fast scroll rather than a cross-fade between two lists.
  Future<void> animateToIndex(
    int index, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) {
    assert(alignment >= 0 && alignment <= 1, 'alignment must be 0..1');
    assert(duration > Duration.zero, 'duration must be positive');
    return _requireBinding().animateToIndex(index, alignment, duration, curve);
  }

  /// Tells the list that [count] items were inserted *before* the anchor, so
  /// the viewport holds still instead of lurching.
  ///
  /// This is the older-history problem. Prepend a page of messages to a normal
  /// list and every index shifts by a page, so what the reader was looking at
  /// slides down the screen. The usual fixes are to measure the inserted items
  /// and subtract their height, or to invert the whole list and think upside
  /// down forever.
  ///
  /// Here the anchor is an index, so the correction is arithmetic on one
  /// integer, and the scroll offset is never touched — the pixels on screen do
  /// not move at all, even mid-item. Call it in the same frame you grow the
  /// list:
  ///
  /// ```dart
  /// setState(() => messages.insertAll(0, older));
  /// controller.itemsInsertedAbove(older.length);
  /// ```
  ///
  /// Items added *after* the anchor need no call: their indices are unchanged.
  void itemsInsertedAbove(int count) {
    assert(count >= 0, 'count cannot be negative');
    if (count != 0) _requireBinding().shiftAnchor(count);
  }

  /// Tells the list that [count] items were removed from *before* the anchor.
  ///
  /// The counterpart to [itemsInsertedAbove] — trimming history off the top,
  /// or dropping items a filter no longer matches.
  void itemsRemovedAbove(int count) {
    assert(count >= 0, 'count cannot be negative');
    if (count != 0) _requireBinding().shiftAnchor(-count);
  }

  /// The index currently anchored at the viewport's zero offset.
  int get anchorIndex => _requireBinding().anchorIndex;

  AnchoredListBinding _requireBinding() {
    final AnchoredListBinding? binding = _binding;
    if (binding == null) {
      throw StateError(
        'This AnchoredListController is not attached to a list yet. Build the '
        'AnchoredList before calling this, or check isAttached.',
      );
    }
    return binding;
  }

  /// Wires a list to this controller. Called by [AnchoredList], not by you.
  void attach(AnchoredListBinding binding) => _binding = binding;

  /// Unwires a list. Called by [AnchoredList], not by you.
  void detach(AnchoredListBinding binding) {
    if (identical(_binding, binding)) _binding = null;
  }

  /// Publishes the latest positions. Called by [AnchoredList], not by you.
  void publishPositions(List<ItemPosition> positions) {
    _positions.value = positions;
  }

  @override
  void dispose() {
    _positions.dispose();
    super.dispose();
  }
}

/// The list-side operations a controller drives.
///
/// Implemented by `AnchoredList`'s state. Public only because the controller
/// has to name it; there is no reason to implement it yourself.
abstract class AnchoredListBinding {
  /// Re-anchors so [index] sits at [alignment] within the viewport.
  void jumpToIndex(int index, double alignment);

  /// Scrolls to [index], animating where there is built content to move
  /// through and re-anchoring first where there is not.
  Future<void> animateToIndex(
    int index,
    double alignment,
    Duration duration,
    Curve curve,
  );

  /// Moves the anchor by [delta] indices without moving the scroll offset,
  /// so the same pixels stay on screen after items shift around it.
  void shiftAnchor(int delta);

  /// The index currently at the viewport's zero scroll offset.
  int get anchorIndex;

  /// The scroll controller driving the viewport.
  ScrollController get scrollController;
}
