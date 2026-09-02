// ignore_for_file: prefer_initializing_formals
// Named parameters cannot start with an underscore, so `this._field` is not
// legal here and the lint's suggested fix does not compile.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'fit_text_group.dart';

/// Lays out an [InlineSpan] at the largest font size that fits its box.
///
/// The whole reason this is a [RenderBox] rather than a `LayoutBuilder` is
/// intrinsic sizing. `LayoutBuilder` throws *"does not support returning
/// intrinsic dimensions"*, which rules any widget built on it out of
/// [IntrinsicHeight], [IntrinsicWidth], and [Table] cells — all of which
/// measure their children before laying them out. Doing the fit during layout
/// means intrinsics can be answered honestly.
class RenderFitText extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  /// Creates the render box.
  RenderFitText({
    required InlineSpan text,
    required TextDirection textDirection,
    required double minFontSize,
    required double maxFontSize,
    required double stepGranularity,
    List<double>? presetFontSizes,
    TextAlign textAlign = TextAlign.start,
    bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip,
    TextScaler textScaler = TextScaler.noScaling,
    int? maxLines,
    Locale? locale,
    StrutStyle? strutStyle,
    TextWidthBasis textWidthBasis = TextWidthBasis.parent,
    TextHeightBehavior? textHeightBehavior,
    FitTextGroup? group,
    bool wrapWords = true,
  }) : assert(
         !_hasPlaceholder(text),
         'FitText.rich cannot fit a span containing a WidgetSpan. Fitting '
         'works by measuring the span at candidate sizes, and a placeholder '
         'has no size until its child has been laid out. Without this the '
         'failure surfaced from inside TextPainter, naming neither FitText '
         'nor the span.',
       ),
       _text = text,
       _group = group,
       _wrapWords = wrapWords,
       _minFontSize = minFontSize,
       _maxFontSize = maxFontSize,
       _stepGranularity = stepGranularity,
       _presetFontSizes = presetFontSizes,
       _painter = TextPainter(
         text: text,
         textAlign: textAlign,
         textDirection: textDirection,
         textScaler: textScaler,
         maxLines: maxLines,
         ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
         locale: locale,
         strutStyle: strutStyle,
         textWidthBasis: textWidthBasis,
         textHeightBehavior: textHeightBehavior,
       ),
       _softWrap = softWrap,
       _overflow = overflow;

  final TextPainter _painter;
  InlineSpan _text;
  double _minFontSize;
  double _maxFontSize;
  double _stepGranularity;
  List<double>? _presetFontSizes;
  bool _softWrap;
  TextOverflow _overflow;
  FitTextGroup? _group;
  bool _wrapWords;
  bool _showingReplacement = false;

  /// The font size chosen at the last layout.
  double get fittedFontSize => _fittedFontSize;
  double _fittedFontSize = 0;

  /// Whether the text still overflowed at the smallest permitted size.
  bool get didOverflow => _didOverflow;
  bool _didOverflow = false;

  /// Whether the overflow replacement is being shown instead of the text.
  bool get showingReplacement => _showingReplacement;

  // ---------------------------------------------------------------- setters

  /// Whether a word too long for its line may be broken across lines.
  ///
  /// False keeps words whole and shrinks until the longest one fits.
  set wrapWords(bool value) {
    if (_wrapWords == value) return;
    _wrapWords = value;
    markNeedsLayout();
  }

  /// The group this text agrees a size with, if any.
  set group(FitTextGroup? value) {
    if (identical(_group, value)) return;
    _group?.remove(this);
    _group = value;
    markNeedsLayout();
  }

  /// The span to lay out.
  set text(InlineSpan value) {
    if (_text == value) return;
    assert(
      !_hasPlaceholder(value),
      'FitText.rich cannot fit a span containing a WidgetSpan. Fitting works '
      'by measuring the span at candidate sizes, and a placeholder has no '
      'size until its child has been laid out.',
    );
    _text = value;
    markNeedsLayout();
  }

  static bool _hasPlaceholder(InlineSpan span) {
    bool found = false;
    span.visitChildren((InlineSpan child) {
      if (child is PlaceholderSpan) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Smallest size the text may shrink to.
  set minFontSize(double value) {
    if (_minFontSize == value) return;
    _minFontSize = value;
    markNeedsLayout();
  }

  /// Largest size the text may grow to.
  set maxFontSize(double value) {
    if (_maxFontSize == value) return;
    _maxFontSize = value;
    markNeedsLayout();
  }

  /// Increment between candidate sizes.
  set stepGranularity(double value) {
    if (_stepGranularity == value) return;
    _stepGranularity = value;
    markNeedsLayout();
  }

  /// An explicit list of sizes to choose from.
  set presetFontSizes(List<double>? value) {
    if (_presetFontSizes == value) return;
    _presetFontSizes = value;
    markNeedsLayout();
  }

  /// Whether the text may wrap.
  set softWrap(bool value) {
    if (_softWrap == value) return;
    _softWrap = value;
    markNeedsLayout();
  }

  /// How to handle text that still does not fit.
  set overflow(TextOverflow value) {
    if (_overflow == value) return;
    _overflow = value;
    _painter.ellipsis = value == TextOverflow.ellipsis ? '…' : null;
    markNeedsLayout();
  }

  /// How the text is aligned within its box.
  set textAlign(TextAlign value) {
    if (_painter.textAlign == value) return;
    _painter.textAlign = value;
    markNeedsLayout();
  }

  /// Reading direction.
  set textDirection(TextDirection value) {
    if (_painter.textDirection == value) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  /// Maximum number of lines.
  set maxLines(int? value) {
    if (_painter.maxLines == value) return;
    _painter.maxLines = value;
    markNeedsLayout();
  }

  /// Accessibility text scaling.
  set textScaler(TextScaler value) {
    if (_painter.textScaler == value) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  /// Locale used for font selection.
  set locale(Locale? value) {
    if (_painter.locale == value) return;
    _painter.locale = value;
    markNeedsLayout();
  }

  /// Strut applied to every line.
  set strutStyle(StrutStyle? value) {
    if (_painter.strutStyle == value) return;
    _painter.strutStyle = value;
    markNeedsLayout();
  }

  /// How the paragraph's width is measured.
  set textWidthBasis(TextWidthBasis value) {
    if (_painter.textWidthBasis == value) return;
    _painter.textWidthBasis = value;
    markNeedsLayout();
  }

  /// Height behaviour for the first and last lines.
  set textHeightBehavior(TextHeightBehavior? value) {
    if (_painter.textHeightBehavior == value) return;
    _painter.textHeightBehavior = value;
    markNeedsLayout();
  }

  // ------------------------------------------------------------------ fitting

  /// Candidate sizes, ascending.
  List<double> get _candidates {
    final List<double>? presets = _presetFontSizes;
    if (presets != null && presets.isNotEmpty) {
      return List<double>.of(presets)..sort();
    }
    final int steps = math.max(
      0,
      ((_maxFontSize - _minFontSize) / _stepGranularity).floor(),
    );
    return <double>[
      for (int i = 0; i <= steps; i++)
        math.min(_minFontSize + i * _stepGranularity, _maxFontSize),
    ];
  }

  /// Rebuilds the span at [fontSize].
  ///
  /// Wrapping the span in a parent carrying the new size does not work: a
  /// child's own explicit `fontSize` wins over its parent's, so a span that
  /// already has a size — which it always does, since the widget merges
  /// `DefaultTextStyle` in — would ignore the parent entirely and every
  /// candidate size would appear to fit.
  ///
  /// The root is therefore set directly, and any nested sizes are scaled by
  /// the same ratio so relative emphasis inside rich text survives.
  InlineSpan _scaled(double fontSize) {
    final double? base = _text.style?.fontSize;
    final double ratio = (base == null || base == 0) ? 1 : fontSize / base;
    return _rescale(_text, ratio, fontSize);
  }

  InlineSpan _rescale(InlineSpan span, double ratio, double? rootSize) {
    if (span is! TextSpan) return span;

    final TextStyle? style = span.style;
    TextStyle? next = style;
    if (rootSize != null) {
      next = (style ?? const TextStyle()).copyWith(fontSize: rootSize);
    } else if (style?.fontSize != null) {
      next = style!.copyWith(fontSize: style.fontSize! * ratio);
    }

    final List<InlineSpan>? children = span.children;
    return TextSpan(
      text: span.text,
      style: next,
      children: children == null
          ? null
          : <InlineSpan>[
              for (final InlineSpan child in children)
                _rescale(child, ratio, null),
            ],
      recognizer: span.recognizer,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  bool _fits(double fontSize, BoxConstraints constraints) {
    _painter
      ..text = _scaled(fontSize)
      ..layout(maxWidth: _softWrap ? constraints.maxWidth : double.infinity);

    if (_painter.didExceedMaxLines) return false;
    if (_painter.height > constraints.maxHeight) return false;
    // A single unbreakable word can be wider than the box even after wrapping.
    if (_painter.width > constraints.maxWidth + precisionErrorTolerance) {
      return false;
    }
    // minIntrinsicWidth is the widest run that cannot be broken — the longest
    // word. Requiring it to fit is what keeps words whole.
    if (!_wrapWords &&
        _painter.minIntrinsicWidth >
            constraints.maxWidth + precisionErrorTolerance) {
      return false;
    }
    return true;
  }

  /// Binary-searches the largest candidate that fits.
  ///
  /// Text metrics grow monotonically with font size, so a bisection is sound
  /// and costs ~log2(n) layouts rather than the n a linear scan would.
  (double, bool) _bestFit(BoxConstraints constraints) {
    final List<double> sizes = _candidates;
    if (sizes.isEmpty) return (_minFontSize, true);

    var low = 0;
    var high = sizes.length - 1;
    var best = -1;
    while (low <= high) {
      final int mid = (low + high) ~/ 2;
      if (_fits(sizes[mid], constraints)) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (best >= 0) return (sizes[best], false);
    // Nothing fits; use the smallest and let the caller decide what to do.
    return (sizes.first, true);
  }

  void _layoutAt(double fontSize, BoxConstraints constraints) {
    _fittedFontSize = fontSize;
    _painter
      ..text = _scaled(fontSize)
      ..layout(
        minWidth: constraints.minWidth,
        maxWidth: _softWrap ? constraints.maxWidth : double.infinity,
      );
  }

  // ------------------------------------------------------------- intrinsics

  @override
  double computeMinIntrinsicWidth(double height) {
    // The narrowest the box can be without the text being unreadable: the
    // widest single word at the smallest permitted size.
    _painter
      ..text = _scaled(_candidates.first)
      ..layout();
    return _painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _painter
      ..text = _scaled(_candidates.last)
      ..layout();
    return _painter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final BoxConstraints constraints = BoxConstraints(maxWidth: width);
    _layoutAt(_bestFit(constraints).$1, constraints);
    return _painter.height;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    assert(!debugNeedsLayout);
    return _painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final (double fontSize, bool overflowed) = _bestFit(constraints);
    if (overflowed && child != null) return child!.getDryLayout(constraints);
    _layoutAt(fontSize, constraints);
    return constraints.constrain(_painter.size);
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    // Without this the framework falls back to a real layout to answer a dry
    // baseline query and asserts — so an IntrinsicHeight around a Row with
    // CrossAxisAlignment.baseline containing a FitText threw in debug, which
    // is the very combination this package exists to make work.
    final (double fontSize, bool overflowed) = _bestFit(constraints);
    if (overflowed && child != null) {
      return child!.getDryBaseline(constraints, baseline);
    }
    _layoutAt(fontSize, constraints);
    return _painter.computeDistanceToActualBaseline(baseline);
  }

  @override
  void performLayout() {
    final (double natural, bool overflowed) = _bestFit(constraints);
    _didOverflow = overflowed;

    // Nothing fit and a replacement was supplied: swap to it in this same
    // layout pass rather than a frame later.
    if (overflowed && child != null) {
      _showingReplacement = true;
      child!.layout(constraints, parentUsesSize: true);
      size = child!.size;
      return;
    }
    _showingReplacement = false;

    double chosen = natural;
    final FitTextGroup? group = _group;
    if (group != null) {
      group.report(this, natural);
      final double? agreed = group.resolvedFontSize;
      // Never larger than this box can take, even if the group's agreed size
      // is momentarily stale.
      if (agreed != null) chosen = math.min(natural, agreed);
    }

    _layoutAt(chosen, constraints);
    size = constraints.constrain(_painter.size);

    // The replacement stays mounted whether or not it is used, so it must
    // still be laid out — collapsed to nothing — or the framework complains
    // about a child that was never measured.
    child?.layout(const BoxConstraints.tightFor(width: 0, height: 0));
  }

  // ------------------------------------------------------------------ paint

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_showingReplacement) {
      context.paintChild(child!, offset);
      return;
    }
    // fade is treated as clip: the gradient shader is not implemented, but
    // containing the text is strictly better than letting it paint across
    // whatever sits next to it.
    if (_overflow == TextOverflow.clip ||
        _overflow == TextOverflow.ellipsis ||
        _overflow == TextOverflow.fade) {
      if (_didOverflow) {
        context.pushClipRect(
          needsCompositing,
          offset,
          Offset.zero & size,
          (PaintingContext inner, Offset shifted) =>
              _painter.paint(inner.canvas, shifted),
        );
        return;
      }
    }
    _painter.paint(context.canvas, offset);
  }

  @override
  bool hitTestSelf(Offset position) => !_showingReplacement;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_showingReplacement || child == null) return false;
    // The replacement sits at the origin and takes this box's whole size, so
    // the position needs no transforming.
    return child!.hitTest(result, position: position);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = false
      ..label = _text.toPlainText()
      ..textDirection = _painter.textDirection;
  }

  @override
  void dispose() {
    _group?.remove(this);
    _painter.dispose();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DoubleProperty('fittedFontSize', _fittedFontSize))
      ..add(DoubleProperty('minFontSize', _minFontSize))
      ..add(DoubleProperty('maxFontSize', _maxFontSize))
      ..add(
        FlagProperty(
          'didOverflow',
          value: _didOverflow,
          ifTrue: 'overflowed at minFontSize',
        ),
      )
      ..add(
        FlagProperty(
          'showingReplacement',
          value: _showingReplacement,
          ifTrue: 'showing overflowReplacement',
        ),
      )
      ..add(
        FlagProperty(
          'wrapWords',
          value: _wrapWords,
          ifFalse: 'words kept whole',
        ),
      );
  }
}
