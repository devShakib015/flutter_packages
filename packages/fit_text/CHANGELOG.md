## 0.1.2

Documentation only.

- Adds a recording to the README and the pub.dev page: the same sentence in a
  box that narrows from 460 to 150 pixels, with `FitText` above and a plain
  `Text` below. At the narrow end `FitText` still shows every word and `Text`
  reads "The qui…".

## 0.1.1

Packaging only — no API or behaviour changes.

- Added `.pubignore`. Previous versions shipped the package's own `test/`
  directory to everyone who depended on it.

## 0.1.0

Initial release.

- `FitText` and `FitText.rich` shrink text to the largest size that fits,
  fitting inside a render object rather than a `LayoutBuilder`.
- Works inside `IntrinsicHeight`, `IntrinsicWidth`, `Table` cells and baseline
  alignment, all of which measure children before laying them out and so throw
  for `LayoutBuilder`-based auto-sizing.
- `FitTextGroup` makes several labels settle on one shared size.
- `minFontSize`, `maxFontSize`, `stepGranularity`, and `presetFontSizes` for
  staying on a type scale.
- Both constructors are `const`, like `Text`.
- `overflowReplacement` swaps in another widget when nothing fits, inside the
  same layout pass rather than a frame later.
- `wrapWords: false` keeps long words whole and shrinks until the longest fits.
- Bisection over the candidate range: roughly six text layouts for the
  defaults rather than dozens.
