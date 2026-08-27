## 0.1.0

Initial release.

- `AnchoredList.builder` — a lazy list that jumps to any index in constant
  time, by re-anchoring a centre sliver rather than cross-fading two lists.
- `AnchoredListController` with `jumpToIndex`, `animateToIndex`, `anchorIndex`
  and an `itemPositions` listenable.
- `ItemPosition` reports each built item's place as a fraction of the viewport.
- One viewport and one set of children, so there is no transition artefact and
  nothing is built twice.

**Not supported:** `shrinkWrap`, and this is not a sliver. Flutter asserts
`!shrinkWrap || center == null`, so a centre-anchored viewport cannot size to
its content — the parameter is absent rather than present and broken.
