import 'package:flutter/foundation.dart';

/// Where one item sits in the viewport, as a fraction of viewport extent.
///
/// Zero is the viewport's leading edge and one is its trailing edge, so an
/// item wholly on screen has `leadingEdge >= 0 && trailingEdge <= 1`. Values
/// outside that range mean the item is partly or wholly scrolled off, which is
/// why they are not clamped.
@immutable
class ItemPosition {
  /// Creates a position.
  const ItemPosition({
    required this.index,
    required this.leadingEdge,
    required this.trailingEdge,
  });

  /// The item's index in the list.
  final int index;

  /// Where the item starts, as a fraction of the viewport.
  final double leadingEdge;

  /// Where the item ends, as a fraction of the viewport.
  final double trailingEdge;

  /// Whether any part of the item is on screen.
  bool get isVisible => trailingEdge > 0 && leadingEdge < 1;

  /// Whether the whole item is on screen.
  bool get isFullyVisible => leadingEdge >= 0 && trailingEdge <= 1;

  /// How much of the viewport the item occupies.
  double get extent => trailingEdge - leadingEdge;

  @override
  bool operator ==(Object other) =>
      other is ItemPosition &&
      other.index == index &&
      other.leadingEdge == leadingEdge &&
      other.trailingEdge == trailingEdge;

  @override
  int get hashCode => Object.hash(index, leadingEdge, trailingEdge);

  @override
  String toString() =>
      'ItemPosition($index, '
      '${leadingEdge.toStringAsFixed(3)}..${trailingEdge.toStringAsFixed(3)})';
}
