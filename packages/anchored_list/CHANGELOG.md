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
