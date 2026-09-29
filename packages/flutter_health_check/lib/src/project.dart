import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A Flutter project on disk: its pubspec, its lockfile and its files.
class FlutterProject {
  FlutterProject._(this.root, this.pubspec, this.lock, this.resolutionRoot);

  /// Loads the project at [path]. Throws [ArgumentError] when there is no
  /// pubspec.yaml.
  factory FlutterProject.load(String path) {
    final root = Directory(p.normalize(p.absolute(path)));
    final pubspecFile = File(p.join(root.path, 'pubspec.yaml'));
    if (!pubspecFile.existsSync()) {
      throw ArgumentError('No pubspec.yaml in ${root.path}');
    }
    final pubspec =
        loadYaml(pubspecFile.readAsStringSync()) as YamlMap? ?? YamlMap();
    // A pub workspace member resolves at the workspace root: one lockfile,
    // one .dart_tool, for every package in it.
    var resolutionRoot = root;
    if (pubspec['resolution'] == 'workspace') {
      for (var d = root.parent; d.path != d.parent.path; d = d.parent) {
        final f = File(p.join(d.path, 'pubspec.yaml'));
        if (f.existsSync() &&
            (loadYaml(f.readAsStringSync()) as YamlMap?)?['workspace'] !=
                null) {
          resolutionRoot = d;
          break;
        }
      }
    }
    final lockFile = File(p.join(resolutionRoot.path, 'pubspec.lock'));
    final lock = lockFile.existsSync()
        ? loadYaml(lockFile.readAsStringSync()) as YamlMap?
        : null;
    return FlutterProject._(root, pubspec, lock, resolutionRoot);
  }

  /// The project directory.
  final Directory root;

  /// The parsed pubspec.yaml.
  final YamlMap pubspec;

  /// The parsed pubspec.lock (the workspace's, for a workspace member), if
  /// there is one.
  final YamlMap? lock;

  /// Where pub resolves this package: the root itself, or its workspace root.
  final Directory resolutionRoot;

  /// Where pub writes .dart_tool/package_config.json for this project.
  File get packageConfig =>
      File(p.join(resolutionRoot.path, '.dart_tool', 'package_config.json'));

  /// The pubspec name, or the folder's.
  String get name => pubspec['name']?.toString() ?? p.basename(root.path);

  /// Whether the pubspec depends on the Flutter SDK.
  bool get isFlutter =>
      (pubspec['dependencies'] as YamlMap?)?.containsKey('flutter') ?? false;

  /// [absolute] relative to [root], with forward slashes on every platform,
  /// so it compares with pubspec paths and git's output.
  String rel(String absolute) =>
      p.split(p.relative(absolute, from: root.path)).join('/');

  /// The file at [relative] inside the project.
  File file(String relative) => File(p.join(root.path, relative));

  /// The directory at [relative] inside the project.
  Directory dir(String relative) => Directory(p.join(root.path, relative));

  /// Whether a file or directory exists at [relative].
  bool exists(String relative) =>
      file(relative).existsSync() || dir(relative).existsSync();

  /// The first of [candidates] that exists, or null.
  File? firstFile(List<String> candidates) {
    for (final c in candidates) {
      final f = file(c);
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// Packages in pubspec.lock. Whether one is direct comes from this
  /// package's pubspec, not the lockfile: in a workspace the lockfile marks
  /// anything a sibling depends on as direct.
  Map<String, LockedPackage> get locked {
    final packages = lock?['packages'] as YamlMap?;
    if (packages == null) return {};
    final main =
        (pubspec['dependencies'] as YamlMap?)?.keys.map((k) => '$k').toSet() ??
        {};
    final dev =
        (pubspec['dev_dependencies'] as YamlMap?)?.keys
            .map((k) => '$k')
            .toSet() ??
        {};
    return {
      for (final e in packages.entries)
        e.key.toString(): LockedPackage(
          name: e.key.toString(),
          dependency: main.contains(e.key)
              ? 'direct main'
              : dev.contains(e.key)
              ? 'direct dev'
              : 'transitive',
          source: (e.value as YamlMap)['source']?.toString() ?? '',
          version: (e.value as YamlMap)['version']?.toString() ?? '',
          url: ((e.value as YamlMap)['description'] is YamlMap)
              ? ((e.value as YamlMap)['description'] as YamlMap)['url']
                    ?.toString()
              : null,
        ),
    };
  }

  /// Files under `flutter: assets:` and `flutter: fonts:`, relative to the
  /// root. Directories expand one level, as Flutter does.
  Set<String> get declaredAssets {
    final flutter = pubspec['flutter'] as YamlMap?;
    final out = <String>{};
    for (final entry in (flutter?['assets'] as YamlList?) ?? YamlList()) {
      final path = entry is YamlMap
          ? entry['path']?.toString()
          : entry?.toString();
      if (path == null) continue;
      if (path.endsWith('/')) {
        final d = dir(path);
        if (!d.existsSync()) continue;
        for (final f in d.listSync().whereType<File>()) {
          if (!p.basename(f.path).startsWith('.DS_Store')) out.add(rel(f.path));
        }
      } else {
        out.add(p.posix.normalize(path));
      }
    }
    for (final family in (flutter?['fonts'] as YamlList?) ?? YamlList()) {
      for (final font
          in ((family as YamlMap)['fonts'] as YamlList?) ?? YamlList()) {
        final asset = (font as YamlMap)['asset']?.toString();
        if (asset != null) out.add(p.posix.normalize(asset));
      }
    }
    return out;
  }

  static const _skipDirs = {
    'build',
    '.dart_tool',
    '.git',
    'Pods',
    '.gradle',
    'node_modules',
    '.fvm',
    '.idea',
    '.vscode',
    'ephemeral',
    '.symlinks',
    'Flutter',
    '.pub-cache',
    '.plugin_symlinks',
    'DerivedData',
    '.cxx',
  };

  /// Every file under [sub] (or the whole project), skipping build output,
  /// dependency caches and generated platform folders.
  Iterable<File> files({
    String sub = '',
    bool Function(String path)? where,
  }) sync* {
    final start = sub.isEmpty ? root : dir(sub);
    if (!start.existsSync()) return;
    final stack = <Directory>[start];
    while (stack.isNotEmpty) {
      final d = stack.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = d.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final e in entries) {
        final name = p.basename(e.path);
        if (e is Directory) {
          if (!_skipDirs.contains(name)) stack.add(e);
        } else if (e is File) {
          if (where == null || where(e.path)) yield e;
        }
      }
    }
  }

  /// Hand-written Dart under [sub]: generated files are not the team's code.
  Iterable<File> dartFiles(String sub) => files(
    sub: sub,
    where: (path) =>
        path.endsWith('.dart') &&
        !RegExp(
          r'\.(g|freezed|gr|mocks|config|pb|pbenum|pbjson|pbserver)\.dart$',
        ).hasMatch(path),
  );
}

/// A package as pubspec.lock records it.
class LockedPackage {
  /// A locked [name] at [version].
  LockedPackage({
    required this.name,
    required this.dependency,
    required this.source,
    required this.version,
    this.url,
  });

  /// The package name.
  final String name;

  /// "direct main" or "direct dev" when this project's pubspec names it,
  /// otherwise "transitive".
  final String dependency;

  /// hosted, git, path or sdk.
  final String source;

  /// The locked version.
  final String version;

  /// The hosted repository, for hosted packages.
  final String? url;

  /// Whether this project's pubspec names it.
  bool get isDirect => dependency.startsWith('direct');

  /// Hosted on pub.dev, so pub.dev and OSV know about it.
  bool get onPubDev =>
      source == 'hosted' &&
      (url == null ||
          url == 'https://pub.dev' ||
          url == 'https://pub.dartlang.org');
}

/// 1-based line number of [offset] in [text].
int lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset.clamp(0, text.length))).length + 1;
