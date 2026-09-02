## 0.2.0

An audit of every package in this repo found five defects here, two of which
broke things this package specifically promises.

### Fixed

- **A `GestureDetector` around a `FitText` never fired.** `RenderFitText` did
  not implement `hitTestSelf`, so the box reported no hit and every wrapping
  gesture detector — and every `TextSpan.recognizer` inside a `FitText.rich` —
  was silently dead. `RenderParagraph` implements it; this did not.
- **`IntrinsicHeight` around a baseline-aligned `Row` threw in debug.**
  `computeDryBaseline` was not overridden, so the framework fell back to a real
  layout to answer a dry baseline query and asserted. Working inside
  `IntrinsicHeight` is the headline reason this package exists —
  `auto_size_text` cannot — so the one combination it was built for was broken.
- **`TextOverflow.fade` was a complete no-op.** Text that did not fit at
  `minFontSize` painted straight over its neighbours. It is now treated as
  `clip`, which contains it; the trailing gradient is still not implemented,
  and the dartdoc says so rather than implying otherwise.
- **A `WidgetSpan` in `FitText.rich` threw from inside `TextPainter`** with
  nothing naming `FitText` as the cause. Fitting measures the span at candidate
  sizes and a placeholder has no size until its child is laid out, so this
  cannot work — it is an assertion that says so now, and the constructor
  documents it.

## 0.1.3

Documentation only — no API changes.

- README code blocks now parse. Several listed variants one per line without
  terminating semicolons, so copying a block gave a syntax error even though
  each individual line was fine. Every snippet in this README is now checked
  through the analyser.

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
