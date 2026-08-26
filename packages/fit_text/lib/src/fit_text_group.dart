import 'dart:math' as math;

import 'package:flutter/scheduler.dart';

import 'render_fit_text.dart';

/// Makes several [FitText] widgets settle on one shared font size.
///
/// Independently fitted labels end up at different sizes, which looks wrong
/// across a row of buttons or a column of list rows. Give them the same group
/// and they all take the smallest size any of them needed, so they match and
/// every one still fits.
///
/// ```dart
/// final labels = FitTextGroup();
///
/// Row(children: [
///   Expanded(child: FitText('Save', group: labels, maxLines: 1)),
///   Expanded(child: FitText('Discard changes', group: labels, maxLines: 1)),
/// ]);
/// ```
///
/// Members find their own size first and agree on the minimum afterwards, so
/// a group settles on the frame after its contents change. Create the group
/// once and hold it in state — rebuilding it every frame defeats it.
class FitTextGroup {
  /// Creates an empty group.
  FitTextGroup();

  final Map<RenderFitText, double> _natural = <RenderFitText, double>{};
  double? _resolved;

  /// The size every member is currently using, or null before the first
  /// member has reported.
  double? get resolvedFontSize => _resolved;

  /// How many members are participating.
  int get length => _natural.length;

  /// Records the size [member] would have chosen on its own.
  ///
  /// Called during layout, so it never marks anything dirty synchronously.
  void report(RenderFitText member, double naturalSize) {
    if (_natural[member] == naturalSize) return;
    _natural[member] = naturalSize;
    _recompute();
  }

  /// Drops a member that is going away.
  void remove(RenderFitText member) {
    if (_natural.remove(member) != null) _recompute();
  }

  void _recompute() {
    final double? next = _natural.values.isEmpty
        ? null
        : _natural.values.reduce(math.min);
    if (next == _resolved) return;
    _resolved = next;

    // Marking another render object dirty during layout is illegal, so the
    // agreement lands on the next frame. That is why a group settles one frame
    // after its contents change.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final RenderFitText member in _natural.keys) {
        if (member.attached) member.markNeedsLayout();
      }
    });
  }
}
