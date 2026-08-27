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
