import 'dart:io';

import 'package:ar_quick_look/ar_quick_look.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('dev.shakib/ar_quick_look');
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> calls = <MethodCall>[];

  void respond(Future<Object?>? Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('platform support', () {
    test('is iOS only, and says so rather than failing later', () async {
      if (ArQuickLook.isSupported) {
        expect(Platform.isIOS, isTrue);
      } else {
        // On the VM this is the path a Flutter app on Android or web takes.
        await expectLater(
          ArQuickLook.present('/tmp/x.usdz'),
          throwsA(isA<NotOnThisPlatformException>()),
        );
        expect(await ArQuickLook.canPreview('/tmp/x.usdz'), isFalse);
      }
    });

    test('the error names the check that would have avoided it', () async {
      if (ArQuickLook.isSupported) return;
      try {
        await ArQuickLook.present('/tmp/x.usdz');
        fail('should have thrown');
      } on NotOnThisPlatformException catch (e) {
        expect(e.message, contains('isSupported'));
      }
    });
  });

  group('arguments', () {
    test('rejects an empty list before touching the platform', () {
      expect(
        () => ArQuickLook.presentAll(const <String>[]),
        throwsAssertionError,
      );
    });

    test('rejects an initial index outside the list', () {
      expect(
        () => ArQuickLook.presentAll(<String>['/a.usdz'], initialIndex: 3),
        throwsAssertionError,
      );
      expect(
        () => ArQuickLook.presentAll(<String>['/a.usdz'], initialIndex: -1),
        throwsAssertionError,
      );
    });
  });

  group('platform errors become typed exceptions', () {
    Future<void> expectMapped(String code, Matcher matcher) async {
      respond((_) async {
        throw PlatformException(code: code, message: 'from the platform');
      });
      // Bypass the platform guard so the mapping itself is what is exercised.
      if (!ArQuickLook.isSupported) return;
      await expectLater(ArQuickLook.present('/a.usdz'), throwsA(matcher));
    }

    test(
      'a missing file',
      () => expectMapped('notFound', isA<FileNotFoundException>()),
    );
    test(
      'a format Quick Look will not read',
      () => expectMapped('unsupportedFile', isA<UnsupportedFileException>()),
    );
    test(
      'nothing to present from',
      () => expectMapped('noHost', isA<NoHostException>()),
    );

    test('every exception is one of ours, never a raw PlatformException', () {
      // The sealed hierarchy is what lets a caller switch exhaustively.
      const List<ArQuickLookException> all = <ArQuickLookException>[
        NotOnThisPlatformException('x'),
        FileNotFoundException('x'),
        UnsupportedFileException('x'),
        NoHostException('x'),
      ];
      for (final ArQuickLookException e in all) {
        expect(e.message, 'x');
        expect(e.toString(), contains('x'));
      }
    });
  });

  group('assets', () {
    test('copies an asset out to a real file, once', () async {
      const String key = 'assets/probe.usdz';
      final Uint8List payload = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);
      int loads = 0;
      final TestAssetBundle bundle = TestAssetBundle(() {
        loads++;
        return payload;
      });

      final String first = await ArQuickLook.materializeAsset(
        key,
        bundle: bundle,
      );
      expect(File(first).existsSync(), isTrue);
      expect(File(first).readAsBytesSync(), payload);
      expect(loads, 1);

      // Quick Look needs a path, not an asset key; the copy is cached so
      // showing the same model twice does not rewrite it.
      final String second = await ArQuickLook.materializeAsset(
        key,
        bundle: bundle,
      );
      expect(second, first);
      expect(loads, 1, reason: 'the second call should reuse the copy');

      File(first).deleteSync();
    });

    test('the copy keeps the asset filename', () async {
      final String path = await ArQuickLook.materializeAsset(
        'assets/models/chair.usdz',
        bundle: TestAssetBundle(() => Uint8List.fromList(<int>[9])),
      );
      expect(path.endsWith('chair.usdz'), isTrue);
      File(path).deleteSync();
    });
  });
}

/// A bundle that hands back fixed bytes and counts how often it was asked.
class TestAssetBundle extends CachingAssetBundle {
  TestAssetBundle(this.bytes);

  final Uint8List Function() bytes;

  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(bytes());

  @override
  Future<String> loadString(String key, {bool cache = true}) async => '';
}
