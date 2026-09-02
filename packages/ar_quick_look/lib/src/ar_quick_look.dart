import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thrown when a preview cannot be shown.
sealed class ArQuickLookException implements Exception {
  /// Creates an exception with a human-readable [message].
  const ArQuickLookException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// AR Quick Look does not exist on this platform.
class NotOnThisPlatformException extends ArQuickLookException {
  /// Creates the exception.
  const NotOnThisPlatformException(super.message);
}

/// The file is not where it was said to be.
class FileNotFoundException extends ArQuickLookException {
  /// Creates the exception.
  const FileNotFoundException(super.message);
}

/// Quick Look will not preview this file.
///
/// Usually the format: AR Quick Look takes `.usdz` and `.reality`. A file with
/// the right extension and the wrong contents fails here too.
class UnsupportedFileException extends ArQuickLookException {
  /// Creates the exception.
  const UnsupportedFileException(super.message);
}

/// A preview is already on screen.
///
/// There is one screen, so there is one viewer. Presenting a second while the
/// first is up used to deallocate the first: the open viewer went blank and
/// its Dart future never completed.
class AlreadyPresentingException extends ArQuickLookException {
  /// Creates the exception.
  const AlreadyPresentingException(super.message);
}

/// Nothing to present from — no view controller was available.
class NoHostException extends ArQuickLookException {
  /// Creates the exception.
  const NoHostException(super.message);
}

/// Apple's AR Quick Look: a 3D model placed in the room through the camera.
///
/// This presents the system viewer rather than rebuilding one. Quick Look
/// already handles placement, scaling, occlusion, shadows, the object/AR
/// toggle and sharing — all of it tuned by Apple and familiar to users from
/// Messages and Safari.
///
/// ```dart
/// await ArQuickLook.present('/path/to/chair.usdz');
/// ```
///
/// The future completes when the user closes the viewer, so `await` covers the
/// whole interaction rather than just the presentation.
class ArQuickLook {
  const ArQuickLook._();

  static const MethodChannel _channel = MethodChannel(
    'dev.shakib/ar_quick_look',
  );

  /// Whether this platform has AR Quick Look at all.
  ///
  /// iOS only. Says nothing about a particular file — use [canPreview] for
  /// that, since the answer depends on the format.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// Whether Quick Look will preview the file at [path].
  ///
  /// False for a missing file, and false for a format Quick Look does not
  /// read — including a `.usdz` extension on something that is not one.
  static Future<bool> canPreview(String path) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('canPreview', <String, Object?>{
          'path': path,
        }) ??
        false;
  }

  /// Shows [path] in AR Quick Look, completing when the user closes it.
  ///
  /// [allowsContentScaling] lets the user resize the model. Turn it off when
  /// the size is the point — furniture in a room, or anything being previewed
  /// to scale.
  ///
  /// [canonicalWebPage] is where Quick Look's Share button points, which is
  /// how a shared model arrives with a link back to the product page rather
  /// than as a bare file.
  static Future<void> present(
    String path, {
    bool allowsContentScaling = true,
    Uri? canonicalWebPage,
  }) => presentAll(
    <String>[path],
    allowsContentScaling: allowsContentScaling,
    canonicalWebPage: canonicalWebPage,
  );

  /// Shows several models, which the user can page between.
  static Future<void> presentAll(
    List<String> paths, {
    int initialIndex = 0,
    bool allowsContentScaling = true,
    Uri? canonicalWebPage,
  }) async {
    assert(paths.isNotEmpty, 'at least one file is required');
    assert(
      initialIndex >= 0 && initialIndex < paths.length,
      'initialIndex must point at one of the files',
    );
    if (!isSupported) {
      throw const NotOnThisPlatformException(
        'AR Quick Look is iOS only. Check ArQuickLook.isSupported first.',
      );
    }
    try {
      await _channel.invokeMethod<void>('present', <String, Object?>{
        'paths': paths,
        'initialIndex': initialIndex,
        'allowsContentScaling': allowsContentScaling,
        'canonicalWebPage': canonicalWebPage?.toString(),
      });
    } on PlatformException catch (e) {
      throw switch (e.code) {
        'notFound' => FileNotFoundException(e.message ?? e.code),
        'unsupportedFile' => UnsupportedFileException(e.message ?? e.code),
        'noHost' => NoHostException(e.message ?? e.code),
        'alreadyPresenting' => AlreadyPresentingException(e.message ?? e.code),
        _ => UnsupportedFileException(e.message ?? e.code),
      };
    }
  }

  /// Shows a model bundled in your Flutter assets.
  ///
  /// Quick Look needs a real file, and a Flutter asset is not one — it lives
  /// inside the app bundle behind the asset system. This copies it out to a
  /// temporary file first, which is the step everyone hits and nobody expects.
  ///
  /// ```dart
  /// await ArQuickLook.presentAsset('assets/models/chair.usdz');
  /// ```
  ///
  /// The copy is cached, so showing the same asset twice writes it once.
  static Future<void> presentAsset(
    String assetKey, {
    bool allowsContentScaling = true,
    Uri? canonicalWebPage,
    AssetBundle? bundle,
  }) async {
    if (!isSupported) {
      throw const NotOnThisPlatformException(
        'AR Quick Look is iOS only. Check ArQuickLook.isSupported first.',
      );
    }
    final String path = await materializeAsset(assetKey, bundle: bundle);
    return present(
      path,
      allowsContentScaling: allowsContentScaling,
      canonicalWebPage: canonicalWebPage,
    );
  }

  /// Copies an asset to a real file and returns its path, reusing the copy if
  /// it is already there.
  ///
  /// Exposed because the same problem appears whenever something outside
  /// Flutter needs a path — sharing a model, handing it to another app — and
  /// solving it once here is better than everyone solving it again.
  ///
  /// The copy is reused if it is already there, so the asset is read once.
  /// That cache lives in the temporary directory and can outlive an app
  /// update, so a build that ships a *changed* model under the same key
  /// should pass `refresh: true` once.
  static Future<String> materializeAsset(
    String assetKey, {
    AssetBundle? bundle,
    bool refresh = false,
  }) async {
    // Namespaced by the whole asset key, not its basename: two assets called
    // model.usdz in different folders used to land on the same temp path and
    // serve each other's bytes — two products, one model. The file keeps its
    // original name inside that directory, so Quick Look still sees a .usdz.
    final String slot = assetKey.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final Directory dir = Directory(
      '${Directory.systemTemp.path}/ar_quick_look/$slot',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final File file = File('${dir.path}/${assetKey.split('/').last}');

    if (!refresh && file.existsSync() && file.lengthSync() > 0) {
      return file.path;
    }

    final ByteData data;
    try {
      data = await (bundle ?? rootBundle).load(assetKey);
    } catch (e) {
      // rootBundle throws a raw FlutterError for a key that is not declared
      // in pubspec.yaml — which escaped the sealed hierarchy entirely, so the
      // commonest setup mistake this package has was not catchable as one of
      // its own.
      throw FileNotFoundException(
        'No asset "$assetKey". Declare it under `assets:` in your '
        'pubspec.yaml, or check the spelling. ($e)',
      );
    }

    // Written beside and renamed. Writing in place meant a write that died
    // half way left a short file that the length check above then trusted
    // forever.
    final File partial = File('${file.path}.part');
    await partial.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await partial.rename(file.path);
    return file.path;
  }
}
