## 0.3.1

No code changes. This release exists because the package was almost impossible
to install.

- **The SDK floor was wrong, and badly.** `sdk: ^3.13.0` meant Dart 3.13, which
  only ships with **Flutter 3.47** — released three weeks ago. Anyone on any
  older SDK hit a version-solve failure before reaching the one-line import
  swap, which is most of the apps this package is for. The floor is now
  `^3.5.0` / Flutter 3.24, and it is *tested*: the library resolves and
  type-checks against Flutter 3.16.9 / Dart 3.2.6, so the declared range is
  narrower than the verified one.
- Two limitations moved from the changelog into the README, because they matter
  in the exact arrangement this package is pitched for: a masonry sliver below
  the cache region is missing from `maxScrollExtent`, and `.builder`/`.custom`
  do not exist yet, so `itemCount` is required where the incumbent allows null.
- `waterfall_flow` is now named in the README as a real alternative that also
  does not have the backwards-scrolling bug.
- Search text: the word "staggered" appeared in neither the description nor the
  topics, while the package it replaces is named for it.

## 0.3.0

An audit of every package in this repo found six defects here, two of which
made tiles disappear or re-measured the whole list. Worth taking.

### Fixed

- **A tile that changed its own size after being measured was never painted
  again.** Children are laid out loose on the main axis with
  `parentUsesSize`, so none of them is a relayout boundary: when a tile
  dirtied itself — a `Image.network` resolving, a font arriving, its own
  `setState` — it marked this sliver dirty but the relayout walk then skipped
  it, so it stayed `_needsLayout` and the framework refused to paint it. The
  tile simply vanished. Every carried-over child is relaid out now;
  `RenderObject.layout` has a fast path for a clean child, so the steady state
  is unchanged, and the never-revise contract holds because the slot still
  comes from `slotOf(index)`.
- **Any ancestor rebuild threw away every placement and re-measured from index
  0.** Invalidation keyed off `delegate.shouldRebuild`, which
  `SliverChildBuilderDelegate` hardcodes to `true` — so a theme change or a
  parent `setState` was enough. It is invisible at the top of a list and
  brutal once the reader has scrolled. Invalidation now tracks the item count,
  which is what actually makes a placement wrong.
- **Columns did not mirror under RTL.** `constraints.crossAxisDirection` was
  ignored while `paint` applies a fixed cross-axis unit vector, so column 0
  stayed on the left. Flutter's own grid delegates carry `reverseCrossAxis`
  for exactly this reason.
- **Spacing wider than the viewport crashed in debug.**
  `crossAxisExtent - spacing × (columns - 1)` went negative and reached
  `BoxConstraints.tightFor`, which asserts. Clamped at zero.

### Known, not fixed

- A masonry sliver sitting entirely below the viewport's cache region reports
  `SliverGeometry.zero`, so `maxScrollExtent` omits it until it is scrolled
  near. Two grids in one `CustomScrollView` show it.
- The catch-up walk holds every child from index 0 to the target window alive
  at once before releasing them, so a long jump has a memory spike.

## 0.2.0

- `MasonryGridView.extent` and `SliverMasonryGrid.extent` size the column count
  to the space available, the way `GridView.extent` does, rather than taking a
  fixed number. A masonry grid is usually a photo feed, and a fixed count
  either wastes a tablet or squeezes a phone — this was the obvious gap against
  every other grid in Flutter.
- Columns are recomputed when the viewport changes width, so a resize or a
  rotation relayouts rather than keeping a stale count.

## 0.1.1

Packaging only — no API or behaviour changes.

- The demo animations now ship inside the package, so they appear as
  screenshots on the pub.dev page rather than only in the README on GitHub.
- `.pubignore` excludes the raw recorder frames, so shipping them costs
  about 600 KB rather than the 11 MB the frame directory would have added.

## 0.1.0

Initial release.

- `MasonryGridView` and `SliverMasonryGrid`, with `.count`, `.list` and
  `.custom` constructors.
- Several `SliverMasonryGrid`s can share one `CustomScrollView` without the
  viewport jumping backwards — the defect
  [flutter_staggered_grid_view#265](https://github.com/letsar/flutter_staggered_grid_view/issues/265)
  has been reporting since 2022. Measured head to head, the incumbent jumps
  twice by up to 3,400px over 45 forward drags; this does not jump.
- Placements are computed once and never revised, so the sliver never issues a
  `scrollOffsetCorrection` and nothing already on screen can move.
- The reported scroll extent uses exact measurements for everything seen and
  estimates only the tail, so the scrollbar drifts by 77px where the incumbent
  drifts by 3,928px and Flutter's own `SliverList` drifts by 1,340px.
- Both axes, `padding`, `shrinkWrap`, `cacheExtent`, `findChildIndexCallback`
  and the rest of the `BoxScrollView` surface.

**Only masonry.** Aligned, quilted, woven and staired layouts are not included:
they are not broken, so replacing them buys nothing.
