// ignore_for_file: prefer_initializing_formals
// Named parameters cannot start with an underscore, so `this._style` is not
// legal and the lint's suggested fix does not compile.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'fit_text_group.dart';
import 'render_fit_text.dart';

/// Text that shrinks to fit the space it is given.
///
/// Flutter has no built-in way to make text fit its box — [Text] either
/// overflows or clips. [FitText] picks the largest size between [minFontSize]
/// and [maxFontSize] at which the text still fits, and lays out at that size.
///
/// ```dart
/// FitText('A headline that must never wrap', maxLines: 1, minFontSize: 12)
/// ```
///
/// ## Why not the alternatives
///
/// The established approach measures inside a `LayoutBuilder`. That works
/// until the widget is placed somewhere Flutter needs an *intrinsic* size
/// first, at which point it throws:
///
/// > LayoutBuilder does not support returning intrinsic dimensions.
///
/// Which rules it out of [IntrinsicHeight], [IntrinsicWidth], and [Table]
/// cells — all of which measure children before laying them out. [FitText]
/// does the fitting inside its own render object during layout, so intrinsics
/// are answered honestly and it works in all of those.
///
/// ## Cost
///
/// Finding the size is a bisection over the candidate range, so roughly
/// `log2((max - min) / stepGranularity)` text layouts — six or so for the
/// defaults, not the dozens a linear scan needs. It re-runs only when the
/// text, style, or constraints change.
class FitText extends SingleChildRenderObjectWidget {
  /// Creates auto-fitting text from a plain [String].
  const FitText(
    String data, {
    super.key,
    TextStyle? style,
    this.minFontSize = 8,
    this.maxFontSize = double.infinity,
    this.stepGranularity = 1,
    this.presetFontSizes,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.strutStyle,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
    this.group,
    this.wrapWords = true,
    Widget? overflowReplacement,
  }) : _data = data,
       _style = style,
       _span = null,
       assert(minFontSize > 0, 'minFontSize must be positive'),
       assert(
         minFontSize <= maxFontSize,
         'minFontSize must not exceed maxFontSize',
       ),
       assert(stepGranularity > 0, 'stepGranularity must be positive'),
       assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       super(child: overflowReplacement);

  /// Creates auto-fitting text from an [InlineSpan].
  ///
  /// Sizes on nested spans are respected relative to nothing — the fitted size
  /// is applied to the root style, so give nested spans relative emphasis
  /// (weight, colour) rather than absolute `fontSize` values.
  /// Fits a rich span.
  ///
  /// [span] must not contain a [WidgetSpan], or any other placeholder: fitting
  /// works by measuring the span at candidate sizes, and a placeholder has no
  /// size until the surrounding render object has laid its child out. A
  /// placeholder used to throw from deep inside `TextPainter` with nothing
  /// naming `FitText.rich` as the cause.
  const FitText.rich(
    InlineSpan span, {
    super.key,
    this.minFontSize = 8,
    this.maxFontSize = double.infinity,
    this.stepGranularity = 1,
    this.presetFontSizes,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap = true,
    this.overflow = TextOverflow.clip,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.strutStyle,
    this.textWidthBasis = TextWidthBasis.parent,
    this.textHeightBehavior,
    this.group,
    this.wrapWords = true,
    Widget? overflowReplacement,
  }) : _span = span,
       _data = null,
       _style = null,
       assert(minFontSize > 0, 'minFontSize must be positive'),
       assert(
         minFontSize <= maxFontSize,
         'minFontSize must not exceed maxFontSize',
       ),
       assert(stepGranularity > 0, 'stepGranularity must be positive'),
       assert(maxLines == null || maxLines > 0, 'maxLines must be positive'),
       super(child: overflowReplacement);

  // Stored unassembled so both constructors can be const, which matters for a
  // widget destined to appear in a lot of build methods.
  final String? _data;
  final TextStyle? _style;
  final InlineSpan? _span;

  /// The span to render.
  InlineSpan get text => _span ?? TextSpan(text: _data, style: _style);

  /// Smallest size the text may shrink to. Below this it overflows instead.
  final double minFontSize;

  /// Largest size the text may grow to.
  ///
  /// Defaults to unbounded, which means the text grows to fill its box. Set it
  /// when you want fitting to shrink but never enlarge.
  final double maxFontSize;

  /// Increment between candidate sizes. Smaller is finer and slightly slower.
  final double stepGranularity;

  /// An explicit set of sizes to choose from, overriding the stepped range.
  ///
  /// Useful for staying on a type scale rather than landing on 17.
  final List<double>? presetFontSizes;

  /// How the text is aligned horizontally.
  final TextAlign? textAlign;

  /// Reading direction. Defaults to the ambient [Directionality].
  final TextDirection? textDirection;

  /// Locale used to pick glyphs.
  final Locale? locale;

  /// Whether the text may wrap.
  final bool softWrap;

  /// What to do when the text does not fit even at [minFontSize].
  ///
  /// [TextOverflow.fade] is treated as [TextOverflow.clip]: the text is
  /// contained, but the trailing gradient `RenderParagraph` draws is not
  /// implemented here. It used to be a complete no-op, which let overflowing
  /// text paint across whatever sat beside it.
  final TextOverflow overflow;

  /// Accessibility text scaling. Defaults to the ambient [MediaQuery].
  final TextScaler? textScaler;

  /// Maximum number of lines.
  final int? maxLines;

  /// An alternative label for screen readers.
  final String? semanticsLabel;

  /// Strut applied to every line.
  final StrutStyle? strutStyle;

  /// How the paragraph's width is measured.
  final TextWidthBasis textWidthBasis;

  /// Height behaviour for the first and last lines.
  final TextHeightBehavior? textHeightBehavior;

  /// Makes this text settle on the same size as every other member.
  ///
  /// Hold the group in state rather than creating one per build.
  final FitTextGroup? group;

  /// Whether a word too long for its line may be broken across lines.
  ///
  /// True matches [Text]. False keeps words whole and shrinks until the
  /// longest one fits, which suits a single unbreakable token such as a
  /// reference number or a URL.
  final bool wrapWords;

  /// Shown instead of the text when nothing fits, even at [minFontSize].
  ///
  /// Swapped in during the same layout pass, so there is no frame where the
  /// overflowing text is visible:
  ///
  /// ```dart
  /// FitText(
  ///   longTitle,
  ///   maxLines: 1,
  ///   minFontSize: 14,
  ///   overflowReplacement: const Icon(Icons.more_horiz),
  /// )
  /// ```
  Widget? get overflowReplacement => child;

  TextStyle _effectiveStyle(BuildContext context) {
    final DefaultTextStyle inherited = DefaultTextStyle.of(context);
    final TextStyle base = inherited.style;
    final TextStyle? own = text.style;
    return own == null ? base : base.merge(own);
  }

  InlineSpan _effectiveSpan(BuildContext context) {
    if (text is TextSpan) {
      final TextSpan span = text as TextSpan;
      return TextSpan(
        text: span.text,
        children: span.children,
        style: _effectiveStyle(context),
        recognizer: span.recognizer,
        semanticsLabel: semanticsLabel ?? span.semanticsLabel,
        locale: span.locale,
        spellOut: span.spellOut,
      );
    }
    return text;
  }

  @override
  RenderFitText createRenderObject(BuildContext context) {
    final DefaultTextStyle inherited = DefaultTextStyle.of(context);
    return RenderFitText(
      text: _effectiveSpan(context),
      textDirection: textDirection ?? Directionality.of(context),
      minFontSize: minFontSize,
      maxFontSize: _resolvedMaxFontSize(context),
      stepGranularity: stepGranularity,
      presetFontSizes: presetFontSizes,
      textAlign: textAlign ?? inherited.textAlign ?? TextAlign.start,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      maxLines: maxLines ?? inherited.maxLines,
      locale: locale,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      group: group,
      wrapWords: wrapWords,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderFitText renderObject) {
    final DefaultTextStyle inherited = DefaultTextStyle.of(context);
    renderObject
      ..text = _effectiveSpan(context)
      ..textDirection = textDirection ?? Directionality.of(context)
      ..minFontSize = minFontSize
      ..maxFontSize = _resolvedMaxFontSize(context)
      ..stepGranularity = stepGranularity
      ..presetFontSizes = presetFontSizes
      ..textAlign = textAlign ?? inherited.textAlign ?? TextAlign.start
      ..softWrap = softWrap
      ..overflow = overflow
      ..textScaler = textScaler ?? MediaQuery.textScalerOf(context)
      ..maxLines = maxLines ?? inherited.maxLines
      ..locale = locale
      ..strutStyle = strutStyle
      ..textWidthBasis = textWidthBasis
      ..textHeightBehavior = textHeightBehavior
      ..group = group
      ..wrapWords = wrapWords;
  }

  /// An unbounded ceiling is unusable as a search bound, so it resolves to the
  /// style's own size when one is set, and a sane cap otherwise.
  double _resolvedMaxFontSize(BuildContext context) {
    if (maxFontSize.isFinite) return maxFontSize;
    final double? styleSize = _effectiveStyle(context).fontSize;
    return styleSize ?? 96;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text.toPlainText(), quoted: false))
      ..add(DoubleProperty('minFontSize', minFontSize))
      ..add(DoubleProperty('maxFontSize', maxFontSize))
      ..add(IntProperty('maxLines', maxLines, defaultValue: null));
  }
}
