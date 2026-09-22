// The channel side, and the sentence a user ends up reading.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_grants/macos_grants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('dev.shakib/macos_grants');
  final List<MethodCall> calls = <MethodCall>[];

  void answer(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('signing', () {
    test('reads what the platform sent', () async {
      answer((_) => <String, Object?>{
            'valid': false,
            'identity': 'adHoc',
            'teamId': null,
            'error': 'nested code is modified or invalid',
          });
      final SigningStatus s = await MacGrants.signing();
      expect(s.valid, isFalse);
      expect(s.identity, SigningIdentity.adHoc);
      expect(s.canHoldGrant, isFalse);
      expect(s.survivesUpdate, isFalse);
      expect(calls.single.method, 'signing');
    }, skip: !MacGrants.isMacOS);

    test('a Developer ID build keeps its grant across updates', () async {
      answer((_) => <String, Object?>{
            'valid': true,
            'identity': 'developerId',
            'teamId': 'ABCDE12345',
          });
      final SigningStatus s = await MacGrants.signing();
      expect(s.survivesUpdate, isTrue);
      expect(s.teamId, 'ABCDE12345');
    }, skip: !MacGrants.isMacOS);

    test('a platform failure is not an accusation', () async {
      // The rule the whole package follows: a check that could not run must
      // never tell somebody their working app is broken.
      answer((_) => throw PlatformException(code: 'boom'));
      final SigningStatus s = await MacGrants.signing();
      expect(s.valid, isTrue);
      expect(s.identity, SigningIdentity.unknown);
    }, skip: !MacGrants.isMacOS);

    test('an unknown identity string does not throw', () async {
      answer((_) => <String, Object?>{'valid': true, 'identity': 'martian'});
      expect((await MacGrants.signing()).identity, SigningIdentity.unknown);
    }, skip: !MacGrants.isMacOS);
  });

  group('off macOS', () {
    test('answers unknown instead of throwing', () async {
      final SigningStatus s = await MacGrants.signing();
      expect(s.identity, SigningIdentity.unknown);
      expect(s.valid, isTrue);
      expect(await MacGrants.fullDiskAccess(), GrantStatus.unknown);
      expect(await MacGrants.accessibility(), GrantStatus.unknown);
      expect(await MacGrants.screenRecording(), GrantStatus.unknown);
      expect(await MacGrants.openSettings(PrivacyPane.fullDiskAccess), isFalse);
      expect(calls, isEmpty);
    }, skip: MacGrants.isMacOS);
  });

  group('what the user is told', () {
    const SigningStatus broken =
        SigningStatus(valid: false, identity: SigningIdentity.developerId);
    const SigningStatus adHoc =
        SigningStatus(valid: true, identity: SigningIdentity.adHoc);
    const SigningStatus proper = SigningStatus(
        valid: true, identity: SigningIdentity.developerId, teamId: 'ABCDE');

    test('a broken bundle is told to reinstall, never to relaunch', () {
      final String said = GrantStatus.denied.explain(broken);
      expect(said, contains('Reinstall'));
      expect(said.toLowerCase(), isNot(contains('relaunch')));
    });

    test('granted is not overruled by a broken signature', () {
      // The app can plainly do the thing; leading with "reinstall" would be
      // the same unhelpful noise as "relaunch" is in the other direction.
      final String said = GrantStatus.granted.explain(broken);
      expect(said, startsWith('Access is granted'));
      expect(said, contains('modified'));
    });

    test('unknown with a broken bundle explains why it may not apply', () {
      expect(GrantStatus.unknown.explain(broken), contains('Reinstall'));
    });

    test('an ad-hoc build warns that the grant will not survive an update', () {
      expect(GrantStatus.denied.explain(adHoc), contains('every update'));
    });

    test('a signed build gets the plain instruction', () {
      final String said = GrantStatus.denied.explain(proper);
      expect(said, contains('System Settings'));
      expect(said, isNot(contains('every update')));
    });

    test('granted says so', () {
      expect(GrantStatus.granted.explain(proper), 'Access is granted.');
    });
  });

  group('settings panes', () {
    test('each pane has its own anchor', () {
      final Set<String> urls =
          PrivacyPane.values.map((PrivacyPane p) => p.url).toSet();
      expect(urls.length, PrivacyPane.values.length);
      expect(PrivacyPane.fullDiskAccess.url, endsWith('Privacy_AllFiles'));
      expect(
        PrivacyPane.screenRecording.url,
        startsWith('x-apple.systempreferences:'),
      );
    });
  });
}
