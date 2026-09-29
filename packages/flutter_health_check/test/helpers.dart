import 'dart:convert';
import 'dart:io';

import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Flutter 3.47.5's numbers, fixed so tests do not depend on the SDK here.
final defaults = FlutterDefaults(
  flutterVersion: '3.47.5',
  targetSdk: 36,
  compileSdk: 36,
  minSdk: 24,
  iosDeploymentTarget: '13.0',
  floors: {
    'gradle': '8.14.0',
    'agp': '8.11.1',
    'kgp': '2.2.20',
    'minSdk': '23',
  },
  warnings: {
    'gradle': '9.1.0',
    'agp': '9.0.1',
    'kgp': '2.3.20',
    'minSdk': '24',
  },
);

final now = DateTime.utc(2026, 9, 29, 12);

const pubspec = '''
name: sample
version: 1.2.0+7
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
''';

/// The Android files `flutter create` writes today.
const templateAppGradle = '''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.shakib.sample"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // TODO: Specify your own unique Application ID.
        applicationId = "dev.shakib.sample"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
''';

const templateSettings = '''
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}
''';

const templateWrapper = r'''
distributionBase=GRADLE_USER_HOME
distributionUrl=https\://services.gradle.org/distributions/gradle-9.3.1-all.zip
''';

const templateManifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="sample" android:name="\${applicationName}">
        <activity android:name=".MainActivity" android:exported="true"/>
    </application>
</manifest>
''';

String plist(String extra, {bool scene = true}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleIdentifier</key>
\t<string>\$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>LSRequiresIPhoneOS</key>
\t<true/>
${scene ? '''\t<key>UIApplicationSceneManifest</key>
\t<dict>
\t\t<key>UIApplicationSupportsMultipleScenes</key>
\t\t<false/>
\t\t<key>UISceneConfigurations</key>
\t\t<dict>
\t\t\t<key>UIWindowSceneSessionRoleApplication</key>
\t\t\t<array>
\t\t\t\t<dict>
\t\t\t\t\t<key>UISceneConfigurationName</key>
\t\t\t\t\t<string>flutter</string>
\t\t\t\t</dict>
\t\t\t</array>
\t\t</dict>
\t</dict>''' : ''}
$extra
</dict>
</plist>
''';

const pbxproj = '''
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.shakib.sample;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = dev.shakib.sample.RunnerTests;
''';

/// A healthy project: every check has something to read and nothing to say.
Map<String, String> healthy() => {
  'pubspec.yaml': pubspec,
  'analysis_options.yaml': 'include: package:flutter_lints/flutter.yaml\n',
  'lib/main.dart': "import 'package:flutter/material.dart';\nvoid main() {}\n",
  'test/app_test.dart':
      "import 'package:flutter_test/flutter_test.dart';\nvoid main() { test('adds', () {}); }\n",
  '.github/workflows/ci.yaml':
      'jobs:\n  test:\n    steps:\n      - run: flutter test\n',
  'android/app/build.gradle.kts': templateAppGradle,
  'android/settings.gradle.kts': templateSettings,
  'android/gradle/wrapper/gradle-wrapper.properties': templateWrapper,
  'android/app/src/main/AndroidManifest.xml': templateManifest,
  'ios/Runner/Info.plist': plist(''),
  'ios/Runner.xcodeproj/project.pbxproj': pbxproj,
};

/// Writes [files] into a fresh temporary directory, deleted after the test.
Directory project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('fhc_test_');
  addTearDown(() => dir.deleteSync(recursive: true));
  files.forEach((path, content) {
    final f = File(p.join(dir.path, path));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  });
  return dir;
}

Future<Report> check(
  Directory dir, {
  http.Client? client,
  bool analyze = false,
}) => audit(
  dir.path,
  network: client != null,
  analyze: analyze,
  client: client,
  defaults: defaults,
  now: now,
);

Set<String> ids(Report r) => {for (final f in r.findings) f.id};

Finding one(Report r, String id) => r.findings.singleWhere((f) => f.id == id);

void git(Directory dir, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: dir.path);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}

/// pub.dev and OSV, answered from [packages] and [advisories].
MockClient fakeRegistry({
  Map<String, Map<String, Object?>> packages = const {},
  Map<String, List<Map<String, Object?>>> advisories = const {},
  bool osvDown = false,
}) => MockClient((request) async {
  final url = request.url.toString();
  if (url == 'https://api.osv.dev/v1/querybatch') {
    if (osvDown) return http.Response('unavailable', 503);
    final body = jsonDecode(request.body) as Map<String, Object?>;
    final queries = (body['queries'] as List).cast<Map<String, Object?>>();
    return http.Response(
      jsonEncode({
        'results': [
          for (final q in queries)
            {
              if (advisories[(q['package'] as Map)['name']] != null)
                'vulns': [
                  for (final v in advisories[(q['package'] as Map)['name']]!)
                    {'id': v['id']},
                ],
            },
        ],
      }),
      200,
    );
  }
  final vuln = RegExp(r'^https://api\.osv\.dev/v1/vulns/(.+)$').firstMatch(url);
  if (vuln != null) {
    final v = advisories.values
        .expand((l) => l)
        .firstWhere((v) => v['id'] == vuln[1]);
    return http.Response(jsonEncode(v), 200);
  }
  final m = RegExp(
    r'^https://pub\.dev/api/packages/([\w]+)(/options|/score)?$',
  ).firstMatch(url);
  final pkg = m == null ? null : packages[m[1]];
  if (pkg == null) return http.Response('not found', 404);
  return switch (m![2]) {
    '/options' => http.Response(
      jsonEncode({
        'isDiscontinued': pkg['discontinued'] ?? false,
        'replacedBy': pkg['replacedBy'],
      }),
      200,
    ),
    '/score' => http.Response(
      jsonEncode({
        'grantedPoints': 150,
        'maxPoints': 160,
        'tags': pkg['tags'] ?? ['license:mit'],
      }),
      200,
    ),
    _ => http.Response(
      jsonEncode({
        'name': m[1],
        'latest': {
          'version': pkg['latest'],
          'published': pkg['published'] ?? '2026-08-01T00:00:00Z',
          'pubspec': {
            'name': m[1],
            if (pkg['plugin'] == true)
              'flutter': {
                'plugin': {
                  'platforms': {'android': {}},
                },
              },
          },
        },
      }),
      200,
    ),
  };
});

String lock(Map<String, (String, String)> packages) {
  final b = StringBuffer('packages:\n');
  packages.forEach((name, v) {
    b.writeln('  $name:');
    b.writeln('    dependency: "${v.$2}"');
    b.writeln(
      '    description:\n      name: $name\n      url: "https://pub.dev"',
    );
    b.writeln('    source: hosted');
    b.writeln('    version: "${v.$1}"');
  });
  return b.toString();
}
