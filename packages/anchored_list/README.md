# anchored_list

Jump to any index in a lazy list, instantly.

```dart
final controller = AnchoredListController();

AnchoredList.builder(
  controller: controller,
  itemCount: 1000000,
  itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
);

controller.jumpToIndex(842013);   // same cost as jumping to item 3
```

## The problem

A lazy list cannot say where item 842,013 begins, because it has never built
the 842,012 items above it and does not know how tall they are. Flutter offers
no answer, and the two packages that did are both abandoned —
`scrollable_positioned_list` was archived by Google, and `scroll_to_index` was
last published in 2022. Between them they still serve over a million downloads
a month.

## How this differs

The archived approach builds a **second complete list** anchored at the target
and cross-fades to it. That is why jumping keeps two sets of children alive and
why the transition is visible.

This uses the primitive Flutter already has for the job. A viewport can nominate
a **centre sliver**, and content before it lays out at *negative* scroll offset.
So the list splits in two at the anchor — items before it in one sliver, the
anchor and everything after in another, marked as the centre. Offset zero *is*
the anchor.

Jumping is then just re-splitting. Nothing above the anchor is built, nothing is
measured, and nothing fades. The test suite pins this: starting at index 500,000
in a million-item list builds fewer than 60 widgets, and jumping 300,000 items
costs about what jumping 3 does.

## Where each item is

```dart
ValueListenableBuilder(
  valueListenable: controller.itemPositions,
  builder: (context, positions, _) {
    final first = positions.firstWhere((p) => p.isVisible);
    return Text('Showing item ${first.index}');
  },
);
```

`leadingEdge` and `trailingEdge` are fractions of the viewport — 0 is the top,
1 the bottom — so a scrollbar label, a sticky section header, or edge-triggered
paging all fall out of it directly.

## Alignment

```dart
controller.jumpToIndex(500, alignment: 0.5);   // centred
await controller.animateToIndex(520);          // smooth
```

`animateToIndex` scrolls normally when the target is already built. When it is
far outside the built range there is nothing to scroll *through*, so the list
re-anchors near the target and animates the last stretch. That reads as a fast
scroll rather than a cross-fade.

## What this does not do

**No `shrinkWrap`.** Flutter asserts `!shrinkWrap || center == null`, so a
centre-anchored viewport can never size itself to its content. The parameter is
absent rather than present and broken. If you need shrink-wrapping, use
`ListView(shrinkWrap: true)` and give up constant-time jumps — that trade runs
the other way, and `scrollable_positioned_list` makes it, which is the one thing
its design does better.

**Not a sliver.** It owns its viewport, because owning the viewport is what
makes the centre trick work, so it cannot be nested in another
`CustomScrollView`.

Both follow from the same decision. If they matter more to you than jump cost,
this is the wrong widget, and the README would rather say so than have you find
out in a layout assertion.

## License

MIT © K M Shahriar Hossain
