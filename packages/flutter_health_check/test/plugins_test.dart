import 'dart:convert';

import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:flutter_health_check/src/checks/plugins.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// A plugin's pubspec: [platforms] is the YAML under `flutter: plugin:
/// platforms:`, indented by the caller's map.
String pluginSpec(
  String name, {
  Map<String, String> platforms = const {},
  List<String> deps = const [],
}) {
  final b = StringBuffer('name: $name\nversion: 1.0.0\n');
  if (deps.isNotEmpty) {
    b.writeln('dependencies:');
    for (final d in deps) {
      b.writeln('  $d: any');
    }
  }
  if (platforms.isNotEmpty) {
    b.writeln('flutter:\n  plugin:\n    platforms:');
    platforms.forEach((platform, body) {
      b.writeln('      $platform:');
      for (final line in body.split('\n')) {
        b.writeln('        $line');
      }
    });
  }
  return b.toString();
}

/// The resolved packages every test starts from:
///
/// * url_launcher, Dart only, federated: its iOS and Android code live in
///   url_launcher_ios (a podspec, no Swift package) and url_launcher_android
///   (applies kotlin-android);
/// * camera_ok: one darwin/ folder with a Swift package, and a Kotlin
///   Gradle Plugin line that is commented out;
/// * dart_only: a dartPluginClass, no native code;
/// * dev_plugin: CocoaPods only, but a dev_dependency, never built into the app.
Map<String, Map<String, String>> packages() => {
  'url_launcher': {
    'pubspec.yaml': pluginSpec(
      'url_launcher',
      platforms: {
        'ios': 'default_package: url_launcher_ios',
        'android': 'default_package: url_launcher_android',
      },
      deps: ['url_launcher_ios', 'url_launcher_android'],
    ),
  },
  'url_launcher_ios': {
    'pubspec.yaml': pluginSpec(
      'url_launcher_ios',
      platforms: {'ios': 'pluginClass: URLLauncherPlugin'},
    ),
    'ios/url_launcher_ios.podspec': "Pod::Spec.new do |s|\nend\n",
  },
  'url_launcher_android': {
    'pubspec.yaml': pluginSpec(
      'url_launcher_android',
      platforms: {
        'android':
            'package: io.flutter.plugins.urllauncher\npluginClass: UrlLauncherPlugin',
      },
    ),
    'android/build.gradle':
        "apply plugin: 'com.android.library'\napply plugin: 'kotlin-android'\n",
  },
  'camera_ok': {
    'pubspec.yaml': pluginSpec(
      'camera_ok',
      platforms: {
        'ios': 'pluginClass: CameraPlugin\nsharedDarwinSource: true',
        'android': 'package: dev.ok.camera\npluginClass: CameraPlugin',
      },
    ),
    'darwin/camera_ok.podspec': "Pod::Spec.new do |s|\nend\n",
    'darwin/camera_ok/Package.swift': '// swift-tools-version: 5.9\n',
    'android/build.gradle.kts':
        'plugins {\n    id("com.android.library")\n    // id("org.jetbrains.kotlin.android")\n}\n',
  },
  'dart_only': {
    'pubspec.yaml': pluginSpec(
      'dart_only',
      platforms: {'ios': 'dartPluginClass: DartOnly'},
    ),
  },
  'dev_plugin': {
    'pubspec.yaml': pluginSpec(
      'dev_plugin',
      platforms: {'ios': 'pluginClass: DevPlugin'},
    ),
    'ios/dev_plugin.podspec': "Pod::Spec.new do |s|\nend\n",
  },
};

/// A healthy app that depends on [direct] and [dev], with [pkgs] resolved
/// into a fake pub cache inside the project and listed in package_config.json.
Map<String, String> app({
  Map<String, Map<String, String>>? pkgs,
  List<String> direct = const ['url_launcher', 'camera_ok', 'dart_only'],
  List<String> dev = const ['dev_plugin'],
  bool resolved = true,
}) {
  final all = pkgs ?? packages();
  final files = healthy();
  files['pubspec.yaml'] = [
    'name: sample',
    'version: 1.2.0+7',
    'environment:\n  sdk: ^3.9.0',
    'dependencies:\n  flutter:\n    sdk: flutter',
    for (final d in direct) '  $d: ^1.0.0',
    'dev_dependencies:\n  flutter_test:\n    sdk: flutter\n  flutter_lints: ^6.0.0',
    for (final d in dev) '  $d: ^1.0.0',
    '',
  ].join('\n');
  files['pubspec.lock'] = lock({
    for (final name in all.keys)
      name: (
        name.startsWith('url_launcher_') ? '6.3.0' : '1.0.0',
        direct.contains(name)
            ? 'direct main'
            : dev.contains(name)
            ? 'direct dev'
            : 'transitive',
      ),
  });
  all.forEach((name, pkgFiles) {
    pkgFiles.forEach((path, content) {
      files['cache/$name/$path'] = content;
    });
  });
  if (resolved) {
    files['.dart_tool/package_config.json'] = jsonEncode({
      'configVersion': 2,
      'packages': [
        for (final name in all.keys)
          {
            'name': name,
            'rootUri': '../cache/$name/',
            'packageUri': 'lib/',
            'languageVersion': '3.9',
          },
        {
          'name': 'sample',
          'rootUri': '../',
          'packageUri': 'lib/',
          'languageVersion': '3.9',
        },
      ],
    });
  }
  return files;
}

void main() {
  test('names each plugin that is not ready, and what pulls it in', () async {
    final r = await check(project(app()));

    final pods = one(r, 'ios.cocoapods-only');
    expect(pods.area, Area.ios);
    expect(pods.severity, Severity.low);
    expect(pods.title, '1 plugin has no Swift Package Manager support');
    expect(
      pods.detail,
      startsWith('`url_launcher_ios` 6.3.0 (via url_launcher).'),
    );
    expect(pods.detail, contains('read-only on 2 December 2026'));
    expect(pods.detail, isNot(contains('camera_ok')));
    expect(pods.detail, isNot(contains('dev_plugin')));
    expect(pods.fix, startsWith('Ask the authors'));

    final kotlin = one(r, 'android.kotlin-gradle-plugin');
    expect(kotlin.area, Area.android);
    expect(kotlin.severity, Severity.low);
    expect(kotlin.title, '1 plugin still applies the Kotlin Gradle Plugin');
    expect(
      kotlin.detail,
      startsWith('`url_launcher_android` 6.3.0 (via url_launcher).'),
    );
    expect(kotlin.detail, isNot(contains('camera_ok')));
    expect(kotlin.locations, ['pubspec.yaml']);

    expect(
      r.facts.values['Plugins with native code'],
      '3, 1 without a Swift package, 1 applying the Kotlin Gradle Plugin',
    );
  });

  test(
    'with built-in Kotlin turned on, the Kotlin plugin breaks the build',
    () async {
      final r = await check(
        project({
          ...app(),
          'android/gradle.properties':
              'org.gradle.jvmargs=-Xmx4G\nandroid.builtInKotlin=true\n',
        }),
      );
      final f = one(r, 'android.kotlin-gradle-plugin');
      expect(f.severity, Severity.high);
      expect(
        f.title,
        '1 plugin breaks the Android build with built-in Kotlin on',
      );
      expect(f.locations, ['android/gradle.properties']);
      expect(f.fix, contains('set `android.builtInKotlin=false`'));
    },
  );

  test(
    'a plugin the app lists itself is not reported "via" anything',
    () async {
      final r = await check(
        project(app(direct: ['url_launcher', 'url_launcher_ios'])),
      );
      expect(
        one(r, 'ios.cocoapods-only').detail,
        startsWith('`url_launcher_ios` 6.3.0.'),
      );
    },
  );

  test('no ios/ folder: Swift packages do not matter', () async {
    final files = app()..removeWhere((path, _) => path.startsWith('ios/'));
    final r = await check(project(files));
    expect(ids(r), isNot(contains('ios.cocoapods-only')));
    expect(ids(r), contains('android.kotlin-gradle-plugin'));
  });

  test('packages not resolved: a note, not a finding', () async {
    final r = await check(project(app(resolved: false)));
    expect(ids(r), isNot(contains('ios.cocoapods-only')));
    expect(ids(r), isNot(contains('android.kotlin-gradle-plugin')));
    expect(r.notes.join(), contains('not checked for Swift Package Manager'));
  });

  test('pub.dev says when a newer release has a Swift package', () async {
    final r = await check(
      project(app()),
      client: fakeRegistry(
        packages: {
          'url_launcher_ios': {
            'latest': '6.4.0',
            'plugin': true,
            'tags': ['license:bsd-3-clause', 'is:swiftpm-plugin'],
          },
          'url_launcher_android': {'latest': '6.3.1', 'plugin': true},
        },
      ),
    );
    final f = one(r, 'ios.cocoapods-only');
    expect(
      f.fix,
      'Upgrade `url_launcher_ios` to 6.4.0: that release ships a Swift package.',
    );
  });

  test('a discontinued plugin is called out: it will not move', () async {
    final r = await check(
      project(app()),
      client: fakeRegistry(
        packages: {
          'url_launcher_android': {
            'latest': '6.3.0',
            'plugin': true,
            'discontinued': true,
          },
        },
      ),
    );
    expect(
      one(r, 'android.kotlin-gradle-plugin').fix,
      endsWith(
        '`url_launcher_android` is discontinued and will not move: replace it.',
      ),
    );
  });

  group('appliesKotlinGradlePlugin', () {
    for (final (gradle, applies) in [
      ("apply plugin: 'kotlin-android'", true),
      ('apply plugin: "org.jetbrains.kotlin.android"', true),
      ('plugins {\n    id("kotlin-android")\n}', true),
      ("plugins {\n    id 'org.jetbrains.kotlin.android'\n}", true),
      ('plugins {\n    kotlin("android")\n}', true),
      ("// apply plugin: 'kotlin-android'", false),
      ("/* id 'kotlin-android' */\napply plugin: 'com.android.library'", false),
      ('plugins {\n    id("com.android.library")\n}', false),
      ('url "https://example.com/kotlin-android"', false),
      // health_bridge 2.0.0: applied only below AGP 9, so it has migrated.
      (
        "def isAgp9OrAbove = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION"
            ".tokenize('.')[0].toInteger() >= 9\n"
            "apply plugin: 'com.android.library'\n"
            "if (!isAgp9OrAbove) {\n    apply plugin: 'kotlin-android'\n}",
        false,
      ),
      (
        'if (!project.hasProperty("android.builtInKotlin")) {\n'
            '    apply(plugin = "kotlin-android")\n'
            '    apply plugin: "kotlin-android"\n}',
        false,
      ),
      // An if about something else does not make it conditional on AGP.
      (
        "if (project.hasProperty('flavor')) {\n    apply plugin: 'kotlin-android'\n}",
        true,
      ),
      // Guarded once and applied unconditionally elsewhere still applies it.
      (
        "if (!isAgp9OrAbove) {\n    apply plugin: 'kotlin-android'\n}\n"
            "apply plugin: 'org.jetbrains.kotlin.android'",
        true,
      ),
    ]) {
      test(gradle.replaceAll('\n', ' '), () {
        expect(appliesKotlinGradlePlugin(gradle), applies);
      });
    }
  });
}
