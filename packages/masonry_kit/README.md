# masonry_kit

A staggered / masonry grid for Flutter — Pinterest-style columns of uneven
height, as a sliver or a plain box widget.

Unlike the alternatives, you can put **more than one in the same scroll view**
without the viewport jumping backwards as you scroll.

```dart
MasonryGridView.count(
  crossAxisCount: 2,
  mainAxisSpacing: 8,
  crossAxisSpacing: 8,
  itemCount: photos.length,
  itemBuilder: (context, index) => Photo(photos[index]),
);
```

![A masonry grid scrolling, then reflowing from two columns to four and back](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/masonry_kit/doc/layout.gif)

## The problem


`flutter_staggered_grid_view` does 1.22M downloads a month and has not had a
commit since July 2023. Its tracker has been carrying the same complaint since
2022 — [#265](https://github.com/letsar/flutter_staggered_grid_view/issues/265),
[#244](https://github.com/letsar/flutter_staggered_grid_view/issues/244),
[#286](https://github.com/letsar/flutter_staggered_grid_view/issues/286),
[#338](https://github.com/letsar/flutter_staggered_grid_view/issues/338) —
put two `SliverMasonryGrid`s in one `CustomScrollView` and scrolling throws you
backwards.

Running both packages through one harness, dragging forward 45 times:

| grids in one `CustomScrollView` | `flutter_staggered_grid_view` 0.7.0 | `masonry_kit` |
| --- | --- | --- |
| one | no backward jumps | no backward jumps |
| **two** | **2 jumps, worst 3,400px** | none |
| **four** | **3 jumps, worst 2,200px** | none |

Both panels below are dragged by the same finger, the same distance, at the
same moment. The left one gets thrown back into the first grid:

![The same drag applied to both packages side by side](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/masonry_kit/doc/jump.gif)

## Why it happens

Masonry is sequential: you cannot know where item 400 goes without the measured
heights of the 399 above it. So the usual approach estimates, discovers it was
wrong, and asks the viewport for a `scrollOffsetCorrection`. That is a real part
of the sliver protocol, and it makes the viewport **throw away the layout pass
and start again**.

With one such sliver you mostly get away with it. With two, the second one's
correction restarts the pass, the first — now scrolled well past — re-runs into
its own "ran out of children before reaching the scroll offset" branch, and
hands back a correction the size of its entire offset. That is the 3,400px.

## What this does instead

Measure once, remember, never revise. Each item's column and offset are decided
the first time it is measured and are then permanent, so this sliver has no
reason to ever issue a correction — and it doesn't.

The same property makes the scrollbar honest, because measured items contribute
their exact extent and only the unmeasured tail is estimated:

| worst scrollbar shrink while scrolling | |
| --- | --- |
| `flutter_staggered_grid_view` | 3,928px |
| Flutter's own `SliverList` | 1,340px |
| **`masonry_kit`** | **77px** |

## Sliver or box widget

`MasonryGridView` is the scrollable; `SliverMasonryGrid` is the same layout for
a `CustomScrollView`, and putting several in one is the entire point.

```dart
CustomScrollView(
  slivers: [
    const SliverAppBar(title: Text('Feed')),
    SliverMasonryGrid.count(crossAxisCount: 2, childCount: 40, itemBuilder: ...),
    const SliverToBoxAdapter(child: Divider()),
    SliverMasonryGrid.count(crossAxisCount: 3, childCount: 60, itemBuilder: ...),
  ],
);
```

Both take `mainAxisSpacing`, `crossAxisSpacing` and `crossAxisCount`.
`MasonryGridView` also takes the usual `BoxScrollView` arguments — `padding`,
`physics`, `controller`, `scrollDirection`, `reverse`, `shrinkWrap`,
`cacheExtent`, `findChildIndexCallback` and the rest — and works on either axis.

## What this does not do

**Only masonry.** The package it replaces also ships aligned, quilted, woven and
staired layouts. Those are not broken, so they are not here; if you use them,
stay where you are.

**A grid below the cache region is missing from `maxScrollExtent`.** A masonry
sliver that sits entirely past the viewport's cache window reports zero extent
until it is scrolled near, so the scrollbar under-reports the total until then.
This shows up in exactly the arrangement this package is for — two grids in one
`CustomScrollView` — so it is worth knowing before you adopt it. Fix planned.

**`.builder` and `.custom` are not here yet.** `childCount` / `itemCount` are
required, where the incumbent allows them to be null. Drop-in for `.count` and
`.extent` with a known item count; an unbounded feed is not supported yet.

**A far jump measures its way there.** Because masonry is sequential, jumping to
the far end of an unvisited list has to measure everything in between. Ordinary
scrolling never notices, since the cache grows a screenful at a time, but a
scrollbar dragged from top to bottom of a very long grid will do real work.
That cost is the price of never lying about where an item is.

## Alternatives, honestly

`waterfall_flow` (21k downloads a month, maintained) does not have the
backwards-scrolling bug either, and if it suits you, use it. The difference is
the API: `SliverWaterfallFlow.count` takes a `List<Widget> children`, so lazy
building means restructuring your call site into a delegate. `masonry_kit`
keeps `itemBuilder`, so the switch from `flutter_staggered_grid_view` is an
import line.

`flutter_staggered_grid_view` itself is still the right answer if you need
aligned, quilted, woven or staired layouts, or if you are below Flutter 3.24.

## License

MIT © K M Shahriar Hossain
