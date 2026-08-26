# fit_text

Text that shrinks to fit its box — including in the places auto-sizing usually
breaks.

```dart
FitText('A headline that must never wrap', maxLines: 1, minFontSize: 12)
```

## The problem this fixes

Flutter has no built-in way to make text fit: `Text` overflows or clips. The
established workaround measures inside a `LayoutBuilder`, and that works right
up until the widget lands somewhere Flutter needs an **intrinsic** size first:

```
LayoutBuilder does not support returning intrinsic dimensions.
  at _RenderLayoutBuilder.computeMaxIntrinsicHeight
```

That is a hard framework limitation, not a bug someone forgot to fix. It rules
`LayoutBuilder`-based auto-sizing out of:

- `IntrinsicHeight` and `IntrinsicWidth`
- **`Table` cells** — columns size with intrinsics by default
- Baseline-aligned rows

`FitText` does the fitting inside its own `RenderBox`, during layout. Intrinsics
are answered honestly, so it works in all of those. There is a test in the suite
that pins the `LayoutBuilder` failure alongside `FitText` succeeding in the same
tree, so the difference is verified rather than asserted.

## Install

```yaml
dependencies:
  fit_text: ^0.1.0
```

## Usage

```dart
// Shrink to fit one line, never below 12.
FitText('Long product name', maxLines: 1, minFontSize: 12)

// Grow to fill, but stay on your type scale.
FitText('42', presetFontSizes: [16, 24, 32, 48, 64])

// Rich text — nested sizes scale proportionally.
FitText.rich(
  TextSpan(text: 'Total ', children: [
    TextSpan(text: '£42', style: TextStyle(fontWeight: FontWeight.bold)),
  ]),
  maxLines: 1,
)
```

Both constructors are `const`, like `Text`.

## Matching sizes across widgets

Independently fitted labels land on different sizes, which looks wrong across a
row of buttons. A group makes them agree on the smallest size any member needed,
so they match and all of them still fit.

```dart
final labels = FitTextGroup();   // hold this in state

Row(children: [
  Expanded(child: FitText('Save', group: labels, maxLines: 1)),
  Expanded(child: FitText('Discard changes', group: labels, maxLines: 1)),
]);
```

Members find their own size first and agree on the next frame, so a group
settles one frame after its contents change.

## Options

| | |
| --- | --- |
| `minFontSize` | Floor. Below this the text overflows instead of shrinking further. |
| `maxFontSize` | Ceiling. Defaults to the inherited style's size, so text shrinks but never grows unless you ask. |
| `stepGranularity` | Increment between candidate sizes. |
| `presetFontSizes` | An explicit scale, instead of a stepped range. |
| `group` | Share a size with other members. |

Everything `Text` takes — `textAlign`, `maxLines`, `softWrap`, `overflow`,
`strutStyle`, `textScaler`, `locale`, `textWidthBasis` — behaves the same way.

## Cost

Finding the size is a bisection, not a scan: about `log2((max - min) / step)`
text layouts, so six or so for the defaults. It re-runs only when the text,
style, or constraints change, and `RenderFitText.fittedFontSize` exposes what it
chose if you need to react to it.

## Coming from auto_size_text

The API is deliberately close, so most call sites change only the widget name.

| auto_size_text | fit_text |
| --- | --- |
| `AutoSizeText(...)` | `FitText(...)` |
| `AutoSizeText.rich(...)` | `FitText.rich(...)` |
| `AutoSizeGroup()` | `FitTextGroup()` |
| `group: myGroup` | `group: myGroup` |

| `overflowReplacement:` | `overflowReplacement:` |
| `wrapWords: false` | `wrapWords: false` |

Neither package supports text selection.

One difference worth knowing: `overflowReplacement` stays mounted whether or not
it is used, collapsed to zero size — the same trade `IndexedStack` makes. That
is what lets the swap happen inside a single layout pass with no frame of
overflowing text, but it means an expensive replacement widget is built even
when it never shows. Keep it cheap.

## License

MIT © K M Shahriar Hossain
