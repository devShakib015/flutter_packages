import 'exceptions.dart';
import 'pip_window.dart';

/// Off-web implementation: says no, clearly, and never pretends.
///
/// This is the whole point of the conditional export — a package that only
/// works on the web should still compile everywhere, and fail with something
/// you can read rather than a missing-member error at build time.
class DocumentPipImpl {
  /// Always false: there is no browser here.
  static bool get isSupported => false;

  /// Always throws [DocumentPipUnsupported].
  static Future<PipWindow> open({
    required double width,
    required double height,
    required bool copyStyles,
    required bool disallowReturnToOpener,
    required bool preferInitialWindowPlacement,
  }) async =>
      throw const DocumentPipUnsupported(
        'Document Picture-in-Picture is a browser feature and this is not the '
        'web. Gate the call on DocumentPip.isSupported.',
      );

  /// Always null: nothing is ever open.
  static PipWindow? get current => null;

  /// Always empty: no window was ever opened, so no view came from one.
  static Set<int> get popOutViewIds => const <int>{};
}
