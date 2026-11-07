import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:flutter_health_check/src/checks/advisories.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A healthy app that locks cloud_firestore at [version] as [kind].
Map<String, String> firestore(String version, {String kind = 'direct main'}) =>
    {
      ...healthy(),
      'pubspec.lock': lock({'cloud_firestore': (version, kind)}),
    };

void main() {
  group('the Flutter that builds the app', () {
    for (final (version, fixed) in [
      ('3.47.7', false),
      ('3.47.8', true),
      ('3.47.9', true),
      ('3.50.0', true),
      ('3.24.5', false),
      ('3.47.5@stable', false),
      ('3.50.0-0.1.pre', false),
      ('3.50.0-0.2.pre', true),
      ('3.50.0-0.3.pre', true),
      ('3.49.0-1.0.pre', false),
      ('3.51.0-0.1.pre', true),
    ]) {
      test('$version: ${fixed ? 'has the fix' : 'does not'}', () {
        expect(flutterHasEmudhraFix(version), fixed);
      });
    }

    test('a pin below the fix is high, and says where', () async {
      final r = await check(
        project({...healthy(), '.fvmrc': '{"flutter": "3.47.5"}'}),
      );
      final f = one(r, 'security.emudhra-flutter');
      expect(f.area, Area.security);
      expect(f.severity, Severity.high);
      expect(f.title, startsWith('Flutter 3.47.5 trusts'));
      expect(f.detail, contains('on Android every build'));
      expect(f.detail, contains('GHSA-frr6-h895-5pxp'));
      expect(f.locations, ['.fvmrc']);
    });

    test('a pin at the fix is fine, whatever is on this machine', () async {
      final r = await check(
        project({...healthy(), '.fvmrc': '{"flutter": "3.47.8"}'}),
      );
      expect(ids(r), isNot(contains('security.emudhra-flutter')));
    });

    test('release builds pinned in CI count, and each pin is named', () async {
      final r = await check(
        project({
          ...healthy(),
          '.github/workflows/release.yml':
              'jobs:\n  build:\n    steps:\n      - uses: subosito/flutter-action@v2\n'
              '        with:\n          flutter-version: "3.47.5"\n',
          '.github/workflows/nightly.yml': 'env:\n  FLUTTER_VERSION: 3.41.2\n',
          'codemagic.yaml':
              'workflows:\n  a:\n    environment:\n      flutter: 3.47.9\n',
        }),
      );
      final f = one(r, 'security.emudhra-flutter');
      expect(f.title, startsWith('Flutter 3.41.2 trusts'));
      expect(f.locations, [
        '.github/workflows/nightly.yml:2',
        '.github/workflows/release.yml:6',
      ]);
    });

    test('a composite action can hold the pin', () async {
      final r = await check(
        project({
          ...healthy(),
          '.github/actions/flutter-common/action.yml':
              'runs:\n  steps:\n    - with:\n        channel: stable\n'
              '        flutter-version: 3.41.0\n',
        }),
      );
      expect(one(r, 'security.emudhra-flutter').locations, [
        '.github/actions/flutter-common/action.yml:5',
      ]);
    });

    group('with no pin', () {
      Future<Report> on(String? installed, Map<String, String> files) => audit(
        project(files).path,
        network: false,
        analyze: false,
        defaults: FlutterDefaults(
          flutterVersion: installed,
          floors: defaults.floors,
          warnings: defaults.warnings,
          targetSdk: 36,
          compileSdk: 36,
          minSdk: 24,
          iosDeploymentTarget: '13.0',
        ),
        now: now,
      );

      test('this machine\'s Flutter is medium, and says so', () async {
        final f = one(
          await on('3.47.7', healthy()),
          'security.emudhra-flutter',
        );
        expect(f.severity, Severity.medium);
        expect(f.title, startsWith('Flutter 3.47.7 trusts'));
        expect(f.detail, contains('the one on this machine'));
        expect(f.locations, isEmpty);
      });

      test('Flutter as a submodule: a note, not this machine\'s', () async {
        final r = await on('3.47.7', {
          ...healthy(),
          '.gitmodules':
              '[submodule "submodules/flutter"]\n'
              '\tpath = submodules/flutter\n'
              '\turl = https://github.com/flutter/flutter.git\n',
        });
        expect(ids(r), isNot(contains('security.emudhra-flutter')));
        expect(r.notes.join(), contains('Could not tell which Flutter'));
      });

      test('no Flutter at all: a note', () async {
        final r = await on(null, healthy());
        expect(ids(r), isNot(contains('security.emudhra-flutter')));
        expect(r.notes.join(), contains('Could not tell which Flutter'));
      });
    });

    test('a channel floats, so it is not a pin', () async {
      final r = await check(
        project({
          ...healthy(),
          '.fvmrc': '{"flutter": "stable"}',
          '.github/workflows/release.yml':
              'with:\n  channel: stable\n  flutter-version: 3.x\n',
        }),
      );
      expect(ids(r), isNot(contains('security.emudhra-flutter')));
    });

    test('a commented-out pin is not a pin', () async {
      final r = await check(
        project({
          ...healthy(),
          '.github/workflows/release.yml': '# flutter-version: 3.24.0\n',
        }),
      );
      expect(ids(r), isNot(contains('security.emudhra-flutter')));
    });

    test('no android/, windows/ or linux/: Dart is not affected', () async {
      final files = healthy()
        ..removeWhere((path, _) => path.startsWith('android/'))
        ..['.fvmrc'] = '{"flutter": "3.47.5"}';
      final r = await check(project(files));
      expect(ids(r), isNot(contains('security.emudhra-flutter')));
    });

    test('Linux alone is medium: the system store protects most', () async {
      final files = healthy()
        ..removeWhere((path, _) => path.startsWith('android/'))
        ..addAll({
          '.fvmrc': '{"flutter": "3.47.5"}',
          'linux/CMakeLists.txt': '',
        });
      final f = one(await check(project(files)), 'security.emudhra-flutter');
      expect(f.severity, Severity.medium);
      expect(f.detail, contains('ca-certificates'));
    });
  });

  group('cloud_firestore', () {
    for (final (version, windows, fixed) in [
      ('6.6.0', false, false),
      ('6.10.0', false, false),
      ('6.10.1', false, true),
      ('6.10.1', true, false),
      ('6.10.2', true, true),
      ('7.0.0', false, false),
      ('7.1.0', true, true),
    ]) {
      test('$version${windows ? ' with Windows' : ''}: '
          '${fixed ? 'has the fix' : 'does not'}', () {
        expect(firestoreHasEmudhraFix(version, windows: windows), fixed);
      });
    }

    test('an affected version is high on an app with ios/', () async {
      final f = one(
        await check(project(firestore('7.0.0'))),
        'security.emudhra-firestore',
      );
      expect(f.area, Area.security);
      expect(f.severity, Severity.high);
      expect(f.title, startsWith('cloud_firestore 7.0.0 trusts'));
      expect(f.fix, contains('7.1.0'));
      expect(f.detail, contains('firebase.google.com'));
      expect(f.locations, ['pubspec.yaml']);
    });

    test('a transitive one counts: it is still built into the app', () async {
      final r = await check(project(firestore('6.6.0', kind: 'transitive')));
      expect(ids(r), contains('security.emudhra-firestore'));
    });

    test('a dev_dependency is never built into the app', () async {
      final r = await check(
        project({
          ...firestore('6.6.0', kind: 'direct dev'),
          'pubspec.yaml': '$pubspec  cloud_firestore: ^6.6.0\n',
        }),
      );
      expect(ids(r), isNot(contains('security.emudhra-firestore')));
    });

    test('Android and web only: Firestore is not affected there', () async {
      final files = firestore('6.6.0')
        ..removeWhere((path, _) => path.startsWith('ios/'));
      final r = await check(project(files));
      expect(ids(r), isNot(contains('security.emudhra-firestore')));
    });

    Map<String, String> filesFor(
      Map<String, (String, String)> locked, {
      String deps = '',
      String dev = '',
      bool pods = true,
    }) {
      return {
        ...healthy(),
        'pubspec.yaml': pubspec
            .replaceFirst(
              '    sdk: flutter\ndev_',
              '    sdk: flutter\n$deps\ndev_',
            )
            .replaceFirst(
              'flutter_lints: ^6.0.0\n',
              'flutter_lints: ^6.0.0\n$dev',
            ),
        'pubspec.lock': lock(locked),
        if (pods)
          'ios/Podfile.lock': 'PODS:\n  - Firebase/Firestore (12.15.0)\n',
      };
    }

    test(
      'on 6.x: raise the floors, then name only the FlutterFire packages',
      () async {
        final f = one(
          await check(
            project(
              filesFor(
                {
                  'cloud_firestore': ('6.6.0', 'direct main'),
                  'firebase_core': ('4.11.0', 'direct main'),
                  'firebase_auth': ('6.5.3', 'direct main'),
                  'http': ('1.2.0', 'direct main'),
                  'fake_cloud_firestore': ('4.1.1', 'direct dev'),
                },
                deps:
                    '  cloud_firestore: ^6.5.0\n  firebase_core: ^4.10.0\n  firebase_auth: ^6.5.2\n  http: ^1.2.0',
                dev: '  fake_cloud_firestore: ^4.1.1\n',
              ),
            ),
          ),
          'security.emudhra-firestore',
        ).fix;
        expect(f, contains('`cloud_firestore` to `^6.10.2`'));
        expect(f, contains('`firebase_core` to `^4.15.2`'));
        expect(f, contains('`fake_cloud_firestore` to `^4.2.0`'));
        expect(
          f,
          contains(
            '`flutter pub upgrade cloud_firestore fake_cloud_firestore firebase_auth firebase_core`',
          ),
        );
        expect(f, isNot(contains('http')));
        expect(f, contains('In ios/, run `pod update Firebase` too'));
        expect(f, isNot(contains('--major-versions')));
      },
    );

    test('on 7.0.0: the 7.1.0 floor, and firebase_core 5.1', () async {
      final f = one(
        await check(
          project(
            filesFor(
              {
                'cloud_firestore': ('7.0.0', 'direct main'),
                'firebase_core': ('5.0.0', 'direct main'),
              },
              deps: '  cloud_firestore: ^7.0.0\n  firebase_core: ^5.0.0',
              pods: false,
            ),
          ),
        ),
        'security.emudhra-firestore',
      ).fix;
      expect(f, contains('`cloud_firestore` to `^7.1.0`'));
      expect(f, contains('`firebase_core` to `^5.1.0`'));
      expect(f, isNot(contains('pod update')));
    });

    test('a floor already high enough is left alone', () async {
      final f = one(
        await check(
          project(
            filesFor({
                'cloud_firestore': ('6.10.1', 'direct main'),
                'firebase_core': ('4.15.2', 'direct main'),
              }, deps: '  cloud_firestore: ^6.10.1\n  firebase_core: ^4.15.2')
              ..['windows/CMakeLists.txt'] = '',
          ),
        ),
        'security.emudhra-firestore',
      ).fix;
      expect(f, contains('`cloud_firestore` to `^6.10.2`'));
      expect(f, isNot(contains('`firebase_core` to')));
    });

    test(
      'below 6: every FlutterFire package to its current major at once',
      () async {
        final f = one(
          await check(
            project(
              filesFor(
                {
                  'cloud_firestore': ('5.6.12', 'direct main'),
                  'firebase_core': ('3.15.2', 'direct main'),
                  'firebase_auth': ('5.7.0', 'direct main'),
                },
                deps:
                    '  cloud_firestore: ^5.6.0\n  firebase_core: ^3.10.0\n  firebase_auth: ^5.4.0',
              ),
            ),
          ),
          'security.emudhra-firestore',
        ).fix;
        expect(
          f,
          contains(
            '`flutter pub upgrade --major-versions cloud_firestore firebase_auth firebase_core`',
          ),
        );
        expect(f, contains('7.1.0'));
      },
    );

    test('pulled in by another package: set the floor by listing it', () async {
      final f = one(
        await check(
          project(
            filesFor({
              'cloud_firestore': ('6.6.0', 'transitive'),
              'firebase_core': ('4.11.0', 'transitive'),
              'firebase_ui_firestore': ('2.0.0', 'direct main'),
            }, deps: '  firebase_ui_firestore: ^2.0.0'),
          ),
        ),
        'security.emudhra-firestore',
      ).fix;
      expect(f, contains('add `cloud_firestore: ^6.10.2` to dependencies'));
      expect(
        f,
        contains(
          '`flutter pub upgrade cloud_firestore firebase_core firebase_ui_firestore`',
        ),
      );
    });

    test('a fixed version says nothing', () async {
      final r = await check(project(firestore('7.1.0')));
      expect(ids(r), isNot(contains('security.emudhra-firestore')));
    });
  });

  group('Firebase App Distribution plugin', () {
    Future<Report> withSettings(String line) => check(
      project({
        ...healthy(),
        'android/settings.gradle.kts': '$templateSettings\n$line\n',
      }),
    );

    test('an affected version is medium, with no redeploy', () async {
      final f = one(
        await withSettings(
          'plugins { id("com.google.firebase.appdistribution") version "5.3.0" apply false }',
        ),
        'security.emudhra-app-distribution',
      );
      expect(f.severity, Severity.medium);
      expect(f.fix, contains('5.3.1'));
      expect(f.fix, contains('not need redeploying'));
      expect(f.locations, ['android/settings.gradle.kts']);
    });

    test('the buildscript form is read too', () async {
      final r = await withSettings(
        'dependencies { classpath("com.google.firebase:firebase-appdistribution-gradle:5.0.0") }',
      );
      expect(ids(r), contains('security.emudhra-app-distribution'));
    });

    for (final version in ['5.3.1', '4.2.1', '3.2.1']) {
      test('$version has the fix', () async {
        final r = await withSettings(
          'plugins { id("com.google.firebase.appdistribution") version "$version" }',
        );
        expect(ids(r), isNot(contains('security.emudhra-app-distribution')));
      });
    }

    test('a commented-out plugin says nothing', () async {
      final r = await withSettings(
        '// id("com.google.firebase.appdistribution") version "5.0.0"',
      );
      expect(ids(r), isNot(contains('security.emudhra-app-distribution')));
    });
  });

  group('Play permissions that change in 2027', () {
    Future<Report> withPermissions(List<String> lines) => check(
      project({
        ...healthy(),
        'android/app/src/main/AndroidManifest.xml':
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '${lines.join('\n')}\n'
            '<application android:label="sample"></application>\n</manifest>\n',
      }),
    );
    String use(String name, [String extra = '']) =>
        '<uses-permission android:name="android.permission.$name" $extra/>';

    for (final (permission, date) in [
      ('ACCESS_FINE_LOCATION', '27 January 2027'),
      ('READ_CONTACTS', '27 January 2027'),
      ('MANAGE_CONTACTS', '25 August 2027'),
      ('WRITE_CONTACTS', '25 August 2027'),
      ('ACCESS_LOCAL_NETWORK', '25 August 2027'),
    ]) {
      test('$permission is low until then, and says when', () async {
        final f = one(
          await withPermissions([use(permission)]),
          'android.restricted-permission',
        );
        expect(f.severity, Severity.low);
        expect(f.title, contains(permission));
        expect(f.detail, contains(date));
        expect(f.detail, contains('support.google.com'));
      });
    }

    test('onlyForLocationButton is what Play asks for', () async {
      final r = await withPermissions([
        use(
          'ACCESS_FINE_LOCATION',
          'android:usesPermissionFlags="onlyForLocationButton"',
        ),
      ]);
      expect(ids(r), isNot(contains('android.restricted-permission')));
      expect(
        r.facts.values['Android permissions (app manifest)'],
        'ACCESS_FINE_LOCATION',
      );
    });

    test(
      'READ_CALL_LOG stays high, and adds phone-call verification',
      () async {
        final f = one(
          await withPermissions([use('READ_CALL_LOG')]),
          'android.restricted-permission',
        );
        expect(f.severity, Severity.high);
        expect(f.detail, contains('verifying an account by phone call'));
        expect(f.detail, contains('27 January 2027'));
      },
    );

    test('coarse location is what Play points to', () async {
      final r = await withPermissions([use('ACCESS_COARSE_LOCATION')]);
      expect(ids(r), isNot(contains('android.restricted-permission')));
    });
  });

  test('the JSON names the areas that could not be scored', () async {
    final files = healthy()
      ..removeWhere(
        (path, _) => path.startsWith('android/') || path.startsWith('ios/'),
      );
    final r = await check(project(files));
    expect(r.skipped, isNotEmpty);
    final json = toJson(r);
    for (final area in r.skipped) {
      expect(json, contains('"${area.name}"'));
    }
    expect(json, contains('"skipped"'));
  });
}
