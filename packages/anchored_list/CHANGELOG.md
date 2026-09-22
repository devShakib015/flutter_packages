## 0.3.1

Reported in [issue #3](https://github.com/devShakib015/flutter_packages/issues/3).

### Fixed

- **`animateToIndex` scrolled its ancestors too.** It went through
  `Scrollable.ensureVisible`, which walks *every* enclosing scrollable and
  reveals the target in each one, so a list inside a `TabBarView` could drag
  the horizontal pager with it. It now moves this list's own `ScrollPosition`
  and nothing else.
- **`animateToIndex` refused a zero duration.** It asserted `duration > zero`,
  so a caller passing `Duration.zero` got an assertion in debug and, with
  asserts compiled out, no scroll at all. Zero now means `jumpToIndex`: same
  destination, same alignment, no animation.

## 0.3.0

Items can be dragged into a new order, and a drag can cross the anchor.

Asked for in [issue #2](https://github.com/devShakib015/flutter_packages/issues/2).

### Added

- **`onReorder`**, and with it `onReorderStart`, `onReorderEnd`,
  `proxyDecorator`, `longPressToDrag` and `autoScrollerVelocityScalar`. The
  callback follows `ReorderableListView` exactly, so existing reorder code
  moves across unchanged. Items need a `Key`, and the list needs an `Overlay`
  above it.
- **`AnchoredListDragStartListener`** and
  **`AnchoredListDelayedDragStartListener`**, for putting the drag gesture on a
  handle rather than the whole row.

### Why it is not `SliverReorderableList`

That widget resolves its drop index by walking only the children registered
with itself, and this list is two slivers — one before the anchor, one from the
anchor on. One in each half would be two reorder domains, and a drag over the
anchor would find no drop target and open no gap. Reordering is written against
the list's own index registry instead, which already spans both slivers, so a
drag neither knows nor cares where the split is. Auto-scrolling across the
anchor comes free: the slivers share one scroll space and the anchor is just
offset zero.

A move that steps over the anchor also changes how many items sit above it,
which would slide the viewport by a row. The list corrects the anchor by one,
the same arithmetic `itemsInsertedAbove` does, so the pixels hold still.

## 0.2.1

No code changes. This release exists because the package was almost impossible
to install.

`sdk: ^3.13.0` meant Dart 3.13, which only ships with **Flutter 3.47** —
released three weeks ago. Anyone on an older SDK hit a version-solve failure
before they could try it. The floor is now `^3.5.0` / Flutter 3.24, and it is
tested: the library resolves and type-checks against Flutter 3.16.9 / Dart
3.2.6, so the declared range is narrower than the verified one.

## 0.2.0

An audit of every package in this repo found six defects here, including one in
the feature this package exists for. Worth taking.

### Fixed

- **A prepend was silently dropped when the anchor sat near the end of the
  list.** `itemsInsertedAbove` clamped the new anchor against `itemCount` — but
  it runs between your `setState` and the rebuild that delivers the longer
  list, so that count is still the old one. A chat pinned to the newest message
  is the worst case and the flagship one: the shift was clamped away entirely
  and the reader's content slid down the screen, which is the exact lurch this
  API exists to prevent. The anchor is now held unclamped and clamped on read,
  so the intent survives until the real count arrives. Every prepend test
  anchored mid-list, so nothing caught it; there is now one anchored at the
  last item.
- **An item built with a `GlobalKey` crashed the list.** The child's key was
  copied onto the wrapper widget, leaving two live elements registered under
  the same key: "Multiple widgets used the same GlobalKey" on the first frame.
  Keys are now salted before being lifted, the way
  `SliverChildBuilderDelegate` does it, and unsalted again before
  `findChildIndexCallback` sees them.
- **`reverse: true` put the whole padding in a gap at the anchor.** The inset
  was split by scroll axis alone, ignoring `reverse` and directionality, so
  under a reversed list — the standard chat layout — both anchor-facing edges
  were the ones kept: a blank band mid-content, and no padding at either end.
  The split now resolves the real axis direction first.
- **`animateToIndex` overshot by about a screenful × alignment.** Alignment was
  consumed twice, once as the viewport anchor and once by `ensureVisible`,
  which never reads the anchor. Only `ensureVisible` consumes it now.
- **`jumpToIndex` aligned the item's leading edge, not the item.** So `0.5` was
  not centred and `1.0` scrolled the target off-screen, while `animateToIndex`
  aligned the box — the example had two adjacent buttons disagreeing on the
  same argument. Both now mean what `Scrollable.ensureVisible` means.

## 0.1.1

Packaging only — no API or behaviour changes.

- The demo animations now ship inside the package, so they appear as
  screenshots on the pub.dev page rather than only in the README on GitHub.
- `.pubignore` excludes the raw recorder frames, so shipping them costs
  about 440 KB rather than the 11 MB the frame directory would have added.

## 0.1.0

Initial release.

**Jumping**

- `AnchoredList.builder` — a lazy list that jumps to any index in constant
  time, by re-anchoring a centre sliver rather than cross-fading two lists.
- `AnchoredListController` with `jumpToIndex`, `animateToIndex` and
  `anchorIndex`.
- One viewport and one set of children, so there is no transition artefact and
  nothing is built twice.

**Holding position while the list changes**

- `itemsInsertedAbove` and `itemsRemovedAbove` keep the viewport pixel-still
  when items arrive at or leave the top of the list. Because the anchor is an
  index, the correction is arithmetic on one integer and the scroll offset is
  never touched — nothing moves on screen, even mid-item.
- `findChildIndexCallback` locates items by key so their state survives
  insertions, translated across the two slivers for you.

**Reaching the scroll position**

- `scrollController` may be supplied, and `AnchoredListController
  .scrollController` returns whichever one is in use — enough for a
  `Scrollbar`, page-up/page-down, or linking two lists.
- Offsets are measured from the anchor, so zero is the anchored item and
  content above it is at negative offset.

**Reporting**

- `itemPositions` reports each built item's place as a fraction of the
  viewport, with `isVisible`, `isFullyVisible` and `extent`.

**The rest of the `ListView` surface**

- `AnchoredList.separated` and `AnchoredList(children: [...])`.
- `padding`, `physics`, `reverse`, `scrollDirection`, `cacheExtent`,
  `semanticChildCount`, `dragStartBehavior`, `keyboardDismissBehavior`,
  `scrollBehavior`, `clipBehavior`, `restorationId` and the three `add*` flags.
- `padding` is split between the two slivers rather than applied to both, which
  would double the inset at the anchor.
- Semantic indexes are translated, so items above the anchor announce their
  real list index instead of counting backwards from it.

**Not supported:** `shrinkWrap`, and this is not a sliver. Flutter asserts
`!shrinkWrap || center == null`, so a centre-anchored viewport cannot size to
its content — the parameter is absent rather than present and broken.
