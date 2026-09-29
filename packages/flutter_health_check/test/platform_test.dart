import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('a healthy project has nothing to report', () async {
    final r = await check(project(healthy()));
    expect(r.findings.map((f) => f.id), isEmpty);
    expect(
      r.facts.values['targetSdk'],
      '36 (flutter.targetSdkVersion, Flutter 3.47.5)',
    );
    expect(r.facts.values['Gradle'], '9.3.1');
    expect(r.facts.values['Android Gradle Plugin'], '9.1.0');
    expect(r.overall, 100);
  });

  group('Android', () {
    Future<Report> withGradle(
      String gradle, {
      Map<String, String> extra = const {},
    }) => check(
      project({...healthy(), 'android/app/build.gradle.kts': gradle, ...extra}),
    );

    test('targetSdk below Play\'s requirement is critical', () async {
      final r = await withGradle(
        templateAppGradle.replaceFirst(
          'targetSdk = flutter.targetSdkVersion',
          'targetSdk = 34',
        ),
      );
      final f = one(r, 'android.target-sdk');
      expect(f.severity, Severity.critical);
      expect(f.title, contains('targetSdk is 34'));
      expect(f.detail, contains('hidden from new users'));
      expect(f.locations.single, 'android/app/build.gradle.kts:15');
    });

    test('targetSdk 35 is blocked for updates but not hidden', () async {
      final r = await withGradle(
        templateAppGradle.replaceFirst(
          'targetSdk = flutter.targetSdkVersion',
          'targetSdk = 35',
        ),
      );
      expect(one(r, 'android.target-sdk').detail, isNot(contains('hidden')));
    });

    test('Groovy syntax, and a flavor with a lower target', () async {
      final r = await check(
        project({
          ...healthy()..remove('android/app/build.gradle.kts'),
          'android/app/build.gradle': '''
android {
    defaultConfig {
        applicationId "com.example.sample"
        minSdkVersion 21
        targetSdkVersion flutter.targetSdkVersion
    }
    productFlavors {
        legacy { targetSdkVersion 33 }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
''',
        }),
      );
      expect(
        ids(r),
        containsAll([
          'android.target-sdk',
          'android.example-id',
          'android.debug-signing',
          'android.min-sdk-unsupported',
        ]),
      );
      expect(one(r, 'android.target-sdk').title, contains('33'));
    });

    test('a commented-out target does not count', () async {
      final r = await withGradle(
        templateAppGradle.replaceFirst(
          'targetSdk = flutter.targetSdkVersion',
          'targetSdk = flutter.targetSdkVersion // was: targetSdk = 30',
        ),
      );
      expect(ids(r), isNot(contains('android.target-sdk')));
    });

    test('debug signing in release, not in debug', () async {
      final r = await withGradle(
        templateAppGradle.replaceFirst(
          'signingConfigs.getByName("release")',
          'signingConfigs.getByName("debug")',
        ),
      );
      expect(one(r, 'android.debug-signing').severity, Severity.high);
      final debugOnly = await withGradle(
        templateAppGradle.replaceFirst(
          'buildTypes {',
          'buildTypes {\n        debug { signingConfig = signingConfigs.getByName("debug") }',
        ),
      );
      expect(ids(debugOnly), isNot(contains('android.debug-signing')));
    });

    test(
      'toolchain below Flutter\'s floor fails; below its warning is low',
      () async {
        final r = await check(
          project({
            ...healthy(),
            'android/gradle/wrapper/gradle-wrapper.properties':
                r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.3-all.zip',
            'android/settings.gradle.kts': templateSettings
                .replaceFirst('"9.1.0"', '"9.0.0"')
                .replaceFirst('"2.4.0"', '"1.9.22"'),
          }),
        );
        expect(one(r, 'android.gradle-unsupported').severity, Severity.high);
        expect(one(r, 'android.kgp-unsupported').title, contains('1.9.22'));
        expect(one(r, 'android.agp-deprecated').severity, Severity.low);
      },
    );

    test(
      'a pinned older Flutter still builds it: upgrade work, not a broken build',
      () async {
        final r = await check(
          project({
            ...healthy(),
            '.fvmrc': '{"flutter": "3.24.5"}',
            'android/gradle/wrapper/gradle-wrapper.properties':
                r'distributionUrl=https\://services.gradle.org/distributions/gradle-8.3-all.zip',
          }),
        );
        final f = one(r, 'android.gradle-unsupported');
        expect(f.severity, Severity.medium);
        expect(f.detail, contains('3.24.5 it pins still builds it'));
      },
    );

    test('old-style AGP and Kotlin in the root build.gradle', () async {
      final files = healthy()..remove('android/settings.gradle.kts');
      final r = await check(
        project({
          ...files,
          'android/build.gradle': '''
buildscript {
    ext.kotlin_version = '1.7.10'
    dependencies {
        classpath 'com.android.tools.build:gradle:7.3.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:\$kotlin_version"
    }
}
''',
        }),
      );
      expect(r.facts.values['Android Gradle Plugin'], '7.3.0');
      expect(r.facts.values['Kotlin Gradle Plugin'], '1.7.10');
      expect(
        ids(r),
        containsAll(['android.agp-unsupported', 'android.kgp-unsupported']),
      );
    });

    test('manifest: debuggable, cleartext, restricted permissions', () async {
      final r = await check(
        project({
          ...healthy(),
          'android/app/src/main/AndroidManifest.xml': '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"/>
    <uses-permission android:name="android.permission.READ_SMS" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" tools:node="remove"/>
    <!-- <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/> -->
    <uses-permission android:name="android.permission.health.READ_STEPS"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <application android:debuggable="true" android:usesCleartextTraffic="true"/>
</manifest>
''',
        }),
      );
      final restricted = r.findings
          .where((f) => f.id == 'android.restricted-permission')
          .map((f) => f.title);
      expect(restricted, hasLength(2));
      expect(
        restricted.join(),
        allOf(contains('QUERY_ALL_PACKAGES'), contains('READ_SMS')),
      );
      expect(
        restricted.join(),
        isNot(contains('READ_MEDIA_IMAGES')),
        reason: 'tools:node="remove"',
      );
      expect(
        restricted.join(),
        isNot(contains('MANAGE_EXTERNAL_STORAGE')),
        reason: 'commented out',
      );
      expect(one(r, 'android.debuggable').severity, Severity.critical);
      expect(one(r, 'security.android-cleartext').area, Area.security);
      expect(one(r, 'android.health-connect').title, contains('READ_STEPS'));
      expect(
        ids(r),
        containsAll([
          'android.exact-alarm-denied',
          'android.foreground-service-types',
        ]),
      );
    });

    test(
      'network security config: base cleartext is high, one domain is low',
      () async {
        final r = await check(
          project({
            ...healthy(),
            'android/app/src/main/AndroidManifest.xml': templateManifest
                .replaceFirst(
                  '<application ',
                  '<application android:networkSecurityConfig="@xml/network" ',
                ),
            'android/app/src/main/res/xml/network.xml': '''
<network-security-config>
  <domain-config cleartextTrafficPermitted="true"><domain includeSubdomains="true">legacy.example.net</domain></domain-config>
  <domain-config cleartextTrafficPermitted="true"><domain>10.0.2.2</domain></domain-config>
</network-security-config>
''',
          }),
        );
        expect(
          one(r, 'security.android-cleartext-domains').title,
          contains('legacy.example.net'),
        );
        expect(
          one(r, 'security.android-cleartext-domains').title,
          isNot(contains('10.0.2.2')),
        );
        expect(ids(r), isNot(contains('security.android-cleartext')));
      },
    );

    test('no android folder: area not checked', () async {
      final r = await check(
        project(healthy()..removeWhere((k, _) => k.startsWith('android/'))),
      );
      expect(r.skipped, contains(Area.android));
    });
  });

  group('iOS', () {
    Future<Report> withPlist(
      String extra, {
      bool scene = true,
      Map<String, String> files = const {},
      String? deps,
    }) => check(
      project({
        ...healthy(),
        if (deps != null)
          'pubspec.yaml': pubspec.replaceFirst(
            '    sdk: flutter\n',
            '    sdk: flutter\n$deps',
          ),
        'ios/Runner/Info.plist': plist(extra, scene: scene),
        ...files,
      }),
    );

    test('no scene manifest is high, with the TN3187 source', () async {
      final f = one(
        await withPlist('', scene: false),
        'ios.no-scene-life-cycle',
      );
      expect(f.severity, Severity.high);
      expect(f.fix, contains('tn3187'));
    });

    test('a plugin\'s purpose strings are required for what the app uses', () async {
      final camera = await withPlist(
        '',
        deps: '  image_picker: ^1.1.0\n',
        files: {
          'lib/pick.dart':
              'Future<void> snap() => ImagePicker().pickImage(source: ImageSource.camera);',
        },
      );
      final missing = camera.findings
          .where((f) => f.id == 'ios.missing-purpose-string')
          .toList();
      expect(
        missing.single.title,
        allOf(contains('NSCameraUsageDescription'), contains('`image_picker`')),
      );

      // Gallery only: PHPicker needs no permission, and such apps ship without one.
      final gallery = await withPlist(
        '',
        deps: '  image_picker: ^1.1.0\n',
        files: {
          'lib/pick.dart':
              'Future<void> pick() => ImagePicker().pickImage(source: ImageSource.gallery);',
        },
      );
      expect(ids(gallery), isNot(contains('ios.missing-purpose-string')));
    });

    test('keys from build settings and InfoPlist.strings count', () async {
      final r = await withPlist(
        '',
        deps: '  image_picker: ^1.1.0\n',
        files: {
          'lib/pick.dart': 'final source = ImageSource.camera;',
          'ios/Runner.xcodeproj/project.pbxproj':
              '$pbxproj\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "Scan the code on your ticket.";\n',
          'ios/Runner/en.lproj/InfoPlist.strings':
              '"NSPhotoLibraryUsageDescription" = "Choose a photo of your receipt to attach it.";\n',
        },
      );
      expect(ids(r), isNot(contains('ios.missing-purpose-string')));
    });

    test('permission_handler: what the Dart code requests needs a key', () async {
      final r = await withPlist(
        '',
        deps: '  permission_handler: ^13.0.0\n',
        files: {
          'lib/permissions.dart':
              'Future<void> ask() async { await Permission.microphone.request(); await Permission.activityRecognition.request(); }',
        },
      );
      expect(
        one(r, 'ios.missing-purpose-string').title,
        contains('NSMicrophoneUsageDescription'),
      );
    });

    test('permission_handler through CocoaPods needs the Podfile macro', () async {
      Future<Report> withPodfile(String podfile) => withPlist(
        '<key>NSCameraUsageDescription</key><string>Scan the code on your ticket at the door.</string>',
        deps: '  permission_handler: ^13.0.0\n',
        files: {
          'lib/scan.dart':
              'Future<void> scan() => Permission.camera.request();',
          'ios/Podfile': podfile,
          'ios/Podfile.lock': 'PODS:\n  - permission_handler_apple (9.3.0):\n',
        },
      );
      final missing = await withPodfile(
        "post_install do |installer|\n  # 'PERMISSION_CAMERA=1',\nend\n",
      );
      expect(
        one(missing, 'ios.permission-handler-disabled').fix,
        contains("'PERMISSION_CAMERA=1'"),
      );
      final enabled = await withPodfile(
        "config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['\$(inherited)', 'PERMISSION_CAMERA=1']\n",
      );
      expect(ids(enabled), isNot(contains('ios.permission-handler-disabled')));
    });

    test('purpose strings that name the resource but not the reason', () async {
      final r = await withPlist(
        '<key>NSCameraUsageDescription</key><string>Camera access</string>'
        '<key>NSLocationWhenInUseUsageDescription</key><string>This app needs access to your location.</string>'
        '<key>NSMicrophoneUsageDescription</key><string>Workout voice notes</string>'
        '<key>NSPhotoLibraryUsageDescription</key><string>Workout photos</string>',
      );
      final f = one(r, 'ios.vague-purpose-string');
      expect(f.title, startsWith('2 purpose strings'));
      expect(
        f.detail,
        allOf(
          contains('"Camera access"'),
          contains('"This app needs access to your location."'),
          isNot(contains('Workout')),
        ),
      );
    });

    test('ATS off is high, unless an override makes iOS ignore it', () async {
      const off =
          '<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/></dict>';
      expect(
        one(await withPlist(off), 'security.ios-ats-disabled').severity,
        Severity.high,
      );
      const ignored =
          '<key>NSAppTransportSecurity</key><dict><key>NSAllowsArbitraryLoads</key><true/>'
          '<key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>';
      expect(
        ids(await withPlist(ignored)),
        isNot(contains('security.ios-ats-disabled')),
      );
    });

    test('template bundle ID', () async {
      final r = await withPlist(
        '',
        files: {
          'ios/Runner.xcodeproj/project.pbxproj': pbxproj.replaceAll(
            'dev.shakib.sample',
            'com.example.sample',
          ),
        },
      );
      expect(one(r, 'ios.example-id').title, contains('com.example.sample'));
      expect(one(r, 'ios.example-id').title, isNot(contains('RunnerTests')));
    });
  });
}
