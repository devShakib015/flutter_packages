import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

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

  /// The index currently at the viewport's zero scroll offset.
  int get anchorIndex;
}
