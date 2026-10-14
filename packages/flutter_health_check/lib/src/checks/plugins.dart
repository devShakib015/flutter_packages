import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../context.dart';
import '../model.dart';

/// When the CocoaPods trunk becomes read-only: no new pods, and no new
/// versions of the ones there.
const cocoapodsFreeze = '2 December 2026';

const _swiftPmGuide =
    'https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors';
const _kotlinGuide =
    'https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors';

/// Plugins the app builds with that are not ready for where the platforms
/// are going: no Swift package, so Flutter falls back to CocoaPods for them,
/// or an Android build that applies the Kotlin Gradle Plugin, which AGP 9's
/// built-in Kotlin refuses.
///
/// It reads the versions the lockfile resolved, on disk: pub.dev's
/// `is:swiftpm-plugin` tag only describes the latest release, and the lock is
/// often behind it.
Future<List<Finding>> checkPluginReadiness(CheckContext ctx) async {
  final project = ctx.project;
  final darwin = [
    for (final x in const ['ios', 'macos'])
      if (project.dir(x).existsSync()) x,
  ];
  final android = project.dir('android').existsSync();
  if (darwin.isEmpty && !android) return [];

  final config = project.packageConfig;
  if (!config.existsSync()) {
    ctx.notes.add(
      'Packages are not resolved (no .dart_tool), so plugins were not checked for '
      'Swift Package Manager and built-in Kotlin support. Run `flutter pub get` first.',
    );
    return [];
  }

  final packages = <String, _Package>{};
  for (final (name, dir) in _resolved(config)) {
    if (name == project.name) continue;
    final pkg = _inspect(name, dir);
    if (pkg != null) packages[name] = pkg;
  }

  // Which of the app's own dependencies pulls each package in. A federated
  // plugin's iOS code lives in a package nobody writes down (url_launcher_ios),
  // so a finding names the line the developer can change. dev_dependencies are
  // never built into the app and are left out.
  final via = <String, Set<String>>{};
  final direct = [
    for (final k
        in (project.pubspec['dependencies'] as YamlMap?)?.keys ?? const [])
      '$k',
  ];
  for (final d in direct) {
    final seen = <String>{};
    final queue = [d];
    while (queue.isNotEmpty) {
      final n = queue.removeLast();
      if (!seen.add(n)) continue;
      queue.addAll(packages[n]?.dependencies ?? const []);
    }
    for (final n in seen) {
      via.putIfAbsent(n, () => {}).add(d);
    }
  }

  final built = [
    for (final pkg in packages.values)
      if (via.containsKey(pkg.name)) pkg,
  ]..sort((a, b) => a.name.compareTo(b.name));
  final pods = [
    for (final pkg in built)
      if (pkg.cocoapodsOnly.any(darwin.contains)) pkg.name,
  ];
  final kgp = [
    for (final pkg in built)
      if (android && pkg.appliesKgp) pkg.name,
  ];
  final native = built.where((x) => x.native).length;
  if (native > 0) {
    ctx.facts['Plugins with native code'] = [
      '$native',
      if (darwin.isNotEmpty) '${pods.length} without a Swift package',
      if (android) '${kgp.length} applying the Kotlin Gradle Plugin',
    ].join(', ');
  }
  if (pods.isEmpty && kgp.isEmpty) return [];

  final locked = project.locked;
  String label(String name) {
    final version = locked[name]?.version;
    final from = via[name]!.where((d) => d != name).toList()..sort();
    return [
      '`$name`${version == null || version.isEmpty ? '' : ' $version'}',
      if (from.isNotEmpty && !via[name]!.contains(name))
        '(via ${from.join(', ')})',
    ].join(' ');
  }

  // Whether a newer release fixes it is the difference between "upgrade" and
  // "wait for the author". pub.dev's tag answers that for Swift packages.
  final upgrades = <String, String>{};
  final discontinued = <String>{};
  final pub = ctx.pub;
  if (pub != null) {
    final hosted = {...pods, ...kgp}.where((n) => locked[n]?.onPubDev ?? false);
    final infos = await pub.infos(hosted);
    for (final e in infos.entries) {
      if (e.value.discontinued) discontinued.add(e.key);
      final latest = e.value.latest;
      if (pods.contains(e.key) &&
          e.value.swiftPm &&
          latest != null &&
          latest != locked[e.key]?.version) {
        upgrades[e.key] = latest;
      }
    }
  }
  String gone(List<String> names) {
    final d = names.where(discontinued.contains).toList();
    return d.isEmpty
        ? ''
        : ' ${d.map((n) => '`$n`').join(', ')} ${d.length == 1 ? 'is' : 'are'} '
              'discontinued and will not move: replace ${d.length == 1 ? 'it' : 'them'}.';
  }

  final findings = <Finding>[];
  if (pods.isNotEmpty) {
    final rest = pods.where((n) => !upgrades.containsKey(n)).toList();
    findings.add(
      Finding(
        id: 'ios.cocoapods-only',
        area: Area.ios,
        severity: Severity.low,
        title:
            '${pods.length} plugin${pods.length == 1 ? ' has' : 's have'} no Swift Package '
            'Manager support',
        detail:
            '${pods.map(label).join('; ')}. Flutter builds iOS with Swift Package Manager by '
            'default and falls back to CocoaPods for these. The CocoaPods registry becomes '
            'read-only on $cocoapodsFreeze, so what they pull from it stops getting updates there.',
        fix:
            [
              if (upgrades.isNotEmpty)
                'Upgrade ${upgrades.entries.map((e) => '`${e.key}` to ${e.value}').join(', ')}: '
                    '${upgrades.length == 1 ? 'that release ships' : 'those releases ship'} a Swift package.',
              if (rest.isNotEmpty)
                '${upgrades.isEmpty ? 'Ask' : 'For the rest, ask'} the authors to add one '
                    "(Flutter's guide: $_swiftPmGuide), or plan a replacement.",
            ].join(' ') +
            gone(pods),
        locations: const ['pubspec.yaml'],
      ),
    );
  }

  if (kgp.isNotEmpty) {
    final on = _builtInKotlinOn(project.file('android/gradle.properties'));
    final list = kgp.map(label).join('; ');
    findings.add(
      Finding(
        id: 'android.kotlin-gradle-plugin',
        area: Area.android,
        severity: on ? Severity.high : Severity.low,
        title: on
            ? '${kgp.length} plugin${kgp.length == 1 ? ' breaks' : 's break'} the Android '
                  'build with built-in Kotlin on'
            : '${kgp.length} plugin${kgp.length == 1 ? ' still applies' : 's still apply'} '
                  'the Kotlin Gradle Plugin',
        detail: on
            ? '$list. android/gradle.properties sets `android.builtInKotlin=true`, and AGP 9 '
                  'refuses a plugin that also applies the Kotlin Gradle Plugin, so the build '
                  'fails until these move.'
            : '$list. AGP 9 compiles Kotlin itself and refuses a plugin that also applies '
                  "the Kotlin Gradle Plugin, so the app can't turn on AGP 9's built-in Kotlin "
                  'while it depends on these.',
        fix:
            'Upgrade any whose newer release has migrated (their changelogs say), and ask the '
            "authors of the rest (Flutter's guide: $_kotlinGuide)"
            '${on ? '. Until then, set `android.builtInKotlin=false`.' : '.'}'
            '${gone(kgp)}',
        locations: [on ? 'android/gradle.properties' : 'pubspec.yaml'],
      ),
    );
  }
  return findings;
}

/// True when this Gradle build applies the Kotlin Gradle Plugin on AGP 9.
/// Comments are removed first: they often mention the plugin they used to
/// apply. A plugin that applies it only below AGP 9 (`if (!isAgp9OrAbove)`,
/// or a check of `android.builtInKotlin`) has migrated: health_bridge does
/// this to keep building on older AGP.
bool appliesKotlinGradlePlugin(String gradle) {
  final src = gradle
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAllMapped(
        RegExp(r'(^|[^:])//.*$', multiLine: true),
        (m) => m[1]!,
      );
  final applies = [
    RegExp(
      r'''\bid\s*\(?\s*["'](?:kotlin-android|org\.jetbrains\.kotlin\.android)["']''',
    ),
    RegExp(
      r'''\bapply\s+plugin\s*:\s*["'](?:kotlin-android|org\.jetbrains\.kotlin\.android)["']''',
    ),
    RegExp(r'''\bkotlin\s*\(\s*["']android["']\s*\)'''),
  ];
  return applies.any(
    (re) => re.allMatches(src).any((m) => !_belowAgp9Only(src, m.start)),
  );
}

/// Whether the code at [at] sits inside an `if` whose condition is about the
/// AGP version or built-in Kotlin.
bool _belowAgp9Only(String src, int at) {
  var depth = 0;
  for (var i = at - 1; i >= 0; i--) {
    final c = src[i];
    if (c == '}') {
      depth++;
    } else if (c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      // A block that encloses [at] opens here; what heads it?
      final head = src.substring(i < 300 ? 0 : i - 300, i);
      final cond = RegExp(r'\bif\s*\(([^{}]*)\)\s*$').firstMatch(head)?[1];
      if (cond != null &&
          RegExp(
            r'agp|android_gradle_plugin|builtinkotlin',
          ).hasMatch(cond.toLowerCase())) {
        return true;
      }
    }
  }
  return false;
}

bool _builtInKotlinOn(File properties) =>
    properties.existsSync() &&
    RegExp(
      r'^\s*android\.builtInKotlin\s*=\s*true\s*$',
      multiLine: true,
    ).hasMatch(properties.readAsStringSync());

/// Each package in package_config.json and the directory it resolved to.
Iterable<(String, Directory)> _resolved(File config) sync* {
  Object? json;
  try {
    json = jsonDecode(config.readAsStringSync());
  } on FormatException {
    return;
  }
  final list = json is Map ? json['packages'] : null;
  if (list is! List) return;
  for (final e in list) {
    if (e is! Map || e['name'] is! String || e['rootUri'] is! String) continue;
    final uri = config.uri.resolve(e['rootUri'] as String);
    if (uri.scheme != 'file') continue;
    yield (e['name'] as String, Directory(uri.toFilePath()));
  }
}

class _Package {
  _Package(
    this.name,
    this.dependencies,
    this.native,
    this.cocoapodsOnly,
    this.appliesKgp,
  );

  final String name;
  final List<String> dependencies;

  /// Whether any platform has native code (a `pluginClass` or an FFI plugin).
  final bool native;

  /// The Apple platforms ('ios', 'macos') it ships a podspec for and no
  /// Swift package.
  final List<String> cocoapodsOnly;

  /// Its Android build applies the Kotlin Gradle Plugin.
  final bool appliesKgp;
}

_Package? _inspect(String name, Directory dir) {
  final file = File(p.join(dir.path, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  YamlMap? spec;
  try {
    spec = loadYaml(file.readAsStringSync()) as YamlMap?;
  } on Object {
    return null;
  }
  final deps = [
    for (final k in (spec?['dependencies'] as YamlMap?)?.keys ?? const []) '$k',
  ];
  final platforms =
      ((spec?['flutter'] as YamlMap?)?['plugin'] as YamlMap?)?['platforms']
          as YamlMap?;
  // Native code means a pluginClass or an FFI plugin. A platform with only a
  // dartPluginClass is Dart, and one with only default_package endorses a
  // federated implementation that is a package of its own.
  bool nativeOn(Object? e) =>
      e is YamlMap && (e['pluginClass'] != null || e['ffiPlugin'] == true);

  final pods = <String>[];
  for (final platform in const ['ios', 'macos']) {
    final entry = platforms?[platform];
    if (!nativeOn(entry)) continue;
    // An iOS app builds the plugin's ios/ (or darwin/, with sharedDarwinSource)
    // and never its macos/: one can have a Swift package and the other not.
    final shared = (entry as YamlMap)['sharedDarwinSource'] == true;
    final base = Directory(p.join(dir.path, shared ? 'darwin' : platform));
    if (!base.existsSync()) continue;
    var pod = false, swift = false;
    for (final e in base.listSync()) {
      if (e is File && e.path.endsWith('.podspec')) pod = true;
      if (e is Directory &&
          File(p.join(e.path, 'Package.swift')).existsSync()) {
        swift = true;
      }
    }
    if (pod && !swift) pods.add(platform);
  }

  var kgp = false;
  if (nativeOn(platforms?['android'])) {
    for (final g in const ['build.gradle', 'build.gradle.kts']) {
      final f = File(p.join(dir.path, 'android', g));
      if (f.existsSync() && appliesKotlinGradlePlugin(f.readAsStringSync())) {
        kgp = true;
      }
    }
  }
  final native = [
    'android',
    'ios',
    'macos',
    'windows',
    'linux',
  ].any((x) => nativeOn(platforms?[x]));
  return _Package(name, deps, native, pods, kgp);
}
