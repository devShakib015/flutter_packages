import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What the system actually granted this text view.
///
/// Asked of the live view rather than inferred from the OS version, because
/// the two can disagree — a device on the right OS with Apple Intelligence
/// turned off still reports the behaviour it was configured with.
class TextCapabilities {
  /// Creates a capability report.
  const TextCapabilities({required this.writingTools, required this.genmoji});

  /// Whether Apple's rewrite/proofread/summarise tools are available here.
  final bool writingTools;

  /// Whether Genmoji can be inserted from the keyboard.
  final bool genmoji;

  @override
  String toString() =>
      'TextCapabilities(writingTools: $writingTools, genmoji: $genmoji)';
}

/// Reads and writes the text of an [AppleIntelligenceTextField].
class NativeTextController extends ChangeNotifier {
  MethodChannel? _channel;

  /// Whether a field is attached.
  bool get isAttached => _channel != null;

  /// Wires a field to this controller. Called by the widget, not by you.
  void attach(MethodChannel channel) {
    _channel = channel;
    notifyListeners();
  }

  /// Unwires a field. Called by the widget, not by you.
  void detach() {
    _channel = null;
  }

  MethodChannel _require() {
    final MethodChannel? c = _channel;
    if (c == null) {
      throw StateError(
        'This NativeTextController is not attached to a field yet. Build the '
        'AppleIntelligenceTextField first, or check isAttached.',
      );
    }
    return c;
  }

  /// The current contents, including anything Writing Tools rewrote.
  Future<String> getText() async =>
      await _require().invokeMethod<String>('getText') ?? '';

  /// Replaces the contents.
  Future<void> setText(String text) =>
      _require().invokeMethod<void>('setText', <String, Object?>{'text': text});

  /// What the system granted this particular view.
  Future<TextCapabilities> capabilities() async {
    final Map<Object?, Object?>? reply = await _require()
        .invokeMethod<Map<Object?, Object?>>('capabilities');
    return TextCapabilities(
      writingTools: reply?['writingTools'] as bool? ?? false,
      genmoji: reply?['genmoji'] as bool? ?? false,
    );
  }
}

/// A real system text view, hosted in Flutter, so Apple's text features work.
///
/// Flutter draws its own text. That is why a Flutter [EditableText] never shows
/// Writing Tools and cannot accept Genmoji: Writing Tools attaches to a
/// `UIView`, Genmoji is a property of `UITextInput`, and Flutter's text field
/// is neither as far as the system is concerned.
///
/// This is not a drop-in for Flutter's own text field, and pretending otherwise
/// would waste your time:
///
/// * It is a **platform view**, so it composites differently and costs more
///   than a Flutter widget. Do not put dozens on a screen.
/// * Styling does **not** inherit from your [DefaultTextStyle] or theme. What
///   the constructor exposes is what you get.
/// * It exists on iOS and macOS. Everywhere else it renders [fallback].
///
/// The trade buys you Writing Tools, Genmoji, and the system's own text
/// behaviour — spellcheck, autocorrect, the context menu — for free, because it
/// really is the system's text view.
class AppleIntelligenceTextField extends StatefulWidget {
  /// Creates a native text field.
  const AppleIntelligenceTextField({
    super.key,
    this.controller,
    this.initialText = '',
    this.fontSize = 16,
    this.readOnly = false,
    this.onChanged,
    this.fallback,
  }) : assert(fontSize > 0, 'fontSize must be positive');

  /// Reads and writes the contents.
  final NativeTextController? controller;

  /// The text the field starts with.
  final String initialText;

  /// Point size of the system font used.
  final double fontSize;

  /// Whether editing is disabled.
  final bool readOnly;

  /// Called whenever the contents change, including when Writing Tools
  /// rewrites them or a Genmoji is inserted.
  ///
  /// Those edits happen inside the native view, so without this the only way
  /// to notice them would be to poll [NativeTextController.getText].
  final ValueChanged<String>? onChanged;

  /// Shown on platforms that have no native view to host — everything except
  /// iOS and macOS. Defaults to an empty box, which is rarely what you want.
  final Widget? fallback;

  /// Whether this platform can host the native view at all.
  static bool get isSupported =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  State<AppleIntelligenceTextField> createState() =>
      _AppleIntelligenceTextFieldState();
}

class _AppleIntelligenceTextFieldState
    extends State<AppleIntelligenceTextField> {
  static const String _viewType = 'dev.shakib/apple_intelligence/text';

  @override
  void dispose() {
    widget.controller?.detach();
    super.dispose();
  }

  void _onCreated(int id) {
    final MethodChannel channel = MethodChannel('$_viewType/$id');
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'textChanged') {
        final Object? args = call.arguments;
        if (args is Map) widget.onChanged?.call(args['text'] as String? ?? '');
      }
      return null;
    });
    widget.controller?.attach(channel);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppleIntelligenceTextField.isSupported) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    final Map<String, Object?> params = <String, Object?>{
      'text': widget.initialText,
      'fontSize': widget.fontSize,
      'readOnly': widget.readOnly,
    };
    if (Platform.isIOS) {
      return UiKitView(
        viewType: _viewType,
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        // Without this the native view never sees a touch, so the caret never
        // appears and Writing Tools has nothing to attach to.
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      );
    }
    return AppKitView(
      viewType: _viewType,
      creationParams: params,
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onCreated,
    );
  }
}
