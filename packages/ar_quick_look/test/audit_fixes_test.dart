// Each test pins a defect found by the 2026-09-02 audit.
import 'dart:io';

import 'package:ar_quick_look/ar_quick_look.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A bundle serving a fixed set of assets, so materializeAsset can be
/// exercised without a real app bundle.
class _Bundle extends CachingAssetBundle {
  _Bundle(this._files);
  final Map<String, List<int>> _files;

  @override
  Future<ByteData> load(String key) async {
    final List<int>? bytes = _files[key];
    if (bytes == null) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      String.fromCharCodes(_files[key]!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Only this file's own slots. Deleting the shared ar_quick_look root races
  // the other test file, which runs in a separate isolate and can be mid-write.
  tearDown(() {
    for (final String key in const <String>[
      'assets/chairs/model.usdz',
      'assets/tables/model.usdz',
      'assets/m.usdz',
    ]) {
      final Directory slot = Directory(
        '${Directory.systemTemp.path}/ar_quick_look/'
        '${key.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}',
      );
      if (slot.existsSync()) slot.deleteSync(recursive: true);
    }
  });

  test('two assets with the same filename do not collide', () async {
    // Shipped in 0.1.0: the temp path was keyed on the BASENAME, so
    // assets/chairs/model.usdz and assets/tables/model.usdz wrote to the same
    // file — and because the cache check was `length > 0`, whichever landed
    // first was served for both. Two different products, one model.
    final _Bundle bundle = _Bundle(<String, List<int>>{
      'assets/chairs/model.usdz': <int>[1, 1, 1, 1],
      'assets/tables/model.usdz': <int>[2, 2, 2, 2, 2, 2],
    });

    final String chair = await ArQuickLook.materializeAsset(
      'assets/chairs/model.usdz',
      bundle: bundle,
    );
    final String table = await ArQuickLook.materializeAsset(
      'assets/tables/model.usdz',
      bundle: bundle,
    );

    expect(chair, isNot(table));
    expect(File(chair).readAsBytesSync(), <int>[1, 1, 1, 1]);
    expect(File(table).readAsBytesSync(), <int>[2, 2, 2, 2, 2, 2]);
    // Both still end in .usdz, which is what Quick Look sniffs.
    expect(chair, endsWith('.usdz'));
    expect(table, endsWith('.usdz'));
  });

  test('refresh replaces a cached copy', () async {
    // Shipped in 0.1.0: the cache check was `length > 0`, so an app update
    // that changed a bundled model kept serving the old bytes forever.
    final _Bundle first = _Bundle(<String, List<int>>{
      'assets/m.usdz': <int>[1, 2, 3],
    });
    final String a = await ArQuickLook.materializeAsset(
      'assets/m.usdz',
      bundle: first,
    );
    expect(File(a).readAsBytesSync(), <int>[1, 2, 3]);

    final _Bundle updated = _Bundle(<String, List<int>>{
      'assets/m.usdz': <int>[9, 9, 9, 9, 9],
    });
    // The copy outlives an app update, so a changed model under the same key
    // needs an explicit refresh — reading the asset on every call would undo
    // the read-once guarantee the cache exists for.
    final String b = await ArQuickLook.materializeAsset(
      'assets/m.usdz',
      bundle: updated,
      refresh: true,
    );
    expect(File(b).readAsBytesSync(), <int>[9, 9, 9, 9, 9]);
  });

  test('the same asset twice writes once and returns the same path', () async {
    final _Bundle bundle = _Bundle(<String, List<int>>{
      'assets/m.usdz': <int>[7, 7, 7],
    });
    final String a = await ArQuickLook.materializeAsset(
      'assets/m.usdz',
      bundle: bundle,
    );
    final String b = await ArQuickLook.materializeAsset(
      'assets/m.usdz',
      bundle: bundle,
    );
    expect(a, b);
  });

  test('a missing asset key is catchable, not a raw FlutterError', () async {
    // Shipped in 0.1.0: rootBundle throws a bare FlutterError for an
    // undeclared key, which escaped the sealed hierarchy — so the commonest
    // setup mistake this package has was not catchable as one of its own.
    final _Bundle bundle = _Bundle(<String, List<int>>{});
    await expectLater(
      ArQuickLook.materializeAsset('assets/nope.usdz', bundle: bundle),
      throwsA(
        isA<FileNotFoundException>().having(
          (FileNotFoundException e) => e.message,
          'message',
          contains('pubspec.yaml'),
        ),
      ),
    );
  });

  test('the exception hierarchy is exhaustive and exported', () {
    Object? name(ArQuickLookException e) => switch (e) {
          NotOnThisPlatformException() => 'platform',
          FileNotFoundException() => 'missing',
          UnsupportedFileException() => 'format',
          AlreadyPresentingException() => 'busy',
          NoHostException() => 'host',
        };
    expect(name(const AlreadyPresentingException('x')), 'busy');
  });
}
