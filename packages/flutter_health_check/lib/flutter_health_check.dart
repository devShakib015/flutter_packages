/// Audits a Flutter app before a release: dependencies, store requirements,
/// security, code health, tests and assets.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'src/checks/android.dart';
import 'src/checks/assets.dart';
import 'src/checks/code.dart';
import 'src/checks/dependencies.dart';
import 'src/checks/ios.dart';
import 'src/checks/security.dart';
import 'src/checks/testing.dart';
import 'src/context.dart';
import 'src/facts.dart';
import 'src/model.dart';
import 'src/project.dart';
import 'src/pub_client.dart';

export 'src/facts.dart' show FlutterDefaults, StoreRules;
export 'src/model.dart';
export 'src/report.dart';

/// This package's version, as `fhc --version` prints it.
const toolVersion = '0.1.0';

/// Runs every check on the Flutter project at [path].
///
/// [network] reads pub.dev and the OSV advisory database; [analyze] runs
/// `dart analyze`; [pubGet] lets it run `flutter pub get` first when the
/// packages are not resolved. Finding ids in [waive], and in the project's
/// health_check.yaml, are reported as accepted and left out of the scores.
Future<Report> audit(
  String path, {
  bool network = true,
  bool analyze = true,
  bool pubGet = false,
  Map<String, String> waive = const {},
  http.Client? client,
  FlutterDefaults? defaults,
  DateTime? now,
}) async {
  final project = FlutterProject.load(path);
  final d = defaults ?? FlutterDefaults.detect();
  final pub = network ? PubClient(client: client) : null;
  final ctx = CheckContext(
    project: project,
    defaults: d,
    now: now ?? DateTime.now(),
    pub: pub,
    analyze: analyze,
    pubGet: pubGet,
    dart: d.root == null
        ? 'dart'
        : p.join(d.root!, 'bin', Platform.isWindows ? 'dart.bat' : 'dart'),
    flutter: d.root == null
        ? 'flutter'
        : p.join(
            d.root!,
            'bin',
            Platform.isWindows ? 'flutter.bat' : 'flutter',
          ),
  );

  _projectFacts(ctx);
  final List<Finding> all;
  try {
    all = [
      ...await checkDependencies(ctx),
      ...checkAndroid(ctx),
      ...checkIos(ctx),
      ...checkSecurity(ctx),
      ...await checkCode(ctx),
      ...checkTesting(ctx),
      ...checkAssets(ctx),
    ];
  } finally {
    if (client == null) pub?.close();
  }

  final waivers = {..._projectWaivers(project, ctx), ...waive};
  return Report(
    projectName: project.name,
    generated: ctx.now,
    findings: [
      for (final f in all)
        if (!waivers.containsKey(f.id)) f,
    ],
    waived: [
      for (final f in all)
        if (waivers.containsKey(f.id)) (f, waivers[f.id]!),
    ],
    dependencies: ctx.dependencies,
    facts: ctx.facts,
    notes: ctx.notes,
    skipped: ctx.skipped,
    auditedWith: d.flutterVersion,
  );
}

void _projectFacts(CheckContext ctx) {
  final project = ctx.project;
  final version = project.pubspec['version']?.toString();
  ctx.facts['App version'] = version ?? 'not set';
  ctx.facts['Platforms'] = [
    for (final platform in [
      'android',
      'ios',
      'web',
      'macos',
      'windows',
      'linux',
    ])
      if (project.dir(platform).existsSync()) platform,
  ].join(', ');
  if (!project.isFlutter) {
    ctx.notes.add(
      'pubspec.yaml does not depend on Flutter; the platform checks assume a '
      'Flutter app.',
    );
  }

  final pinned = _pinnedFlutter(project);
  if (pinned != null) {
    ctx.pinnedFlutter = pinned.$1;
    ctx.facts['Flutter pinned by the project'] = '${pinned.$1} (${pinned.$2})';
    final installed = ctx.defaults.flutterVersion;
    if (installed != null && !pinned.$1.startsWith(installed)) {
      ctx.notes.add(
        'The project pins Flutter ${pinned.$1} (${pinned.$2}) but the checks ran '
        'with Flutter $installed. Build-tool limits and analyzer results describe $installed: '
        'what the app meets when it upgrades.',
      );
    }
  }
  if (ctx.defaults.flutterVersion != null) {
    ctx.facts['Audited with'] = 'Flutter ${ctx.defaults.flutterVersion}';
  }
}

/// The Flutter version the project pins with FVM or asdf, and where. The pin
/// can sit at the repository root when the app is in a subfolder.
(String, String)? _pinnedFlutter(FlutterProject project) {
  for (var dir = project.root; ; dir = dir.parent) {
    String rel(String f) =>
        p.relative(p.join(dir.path, f), from: project.root.path);
    for (final (file, key) in [
      ('.fvmrc', 'flutter'),
      ('.fvm/fvm_config.json', 'flutterSdkVersion'),
    ]) {
      final f = File(p.join(dir.path, file));
      if (!f.existsSync()) continue;
      try {
        final v = (jsonDecode(f.readAsStringSync()) as Map)[key]?.toString();
        if (v != null && v.isNotEmpty) return (v, rel(file));
      } on FormatException {
        continue;
      }
    }
    final tools = File(p.join(dir.path, '.tool-versions'));
    if (tools.existsSync()) {
      final m = RegExp(
        r'^flutter\s+(\S+)',
        multiLine: true,
      ).firstMatch(tools.readAsStringSync());
      if (m != null) {
        return (m[1]!.replaceAll('-stable', ''), rel('.tool-versions'));
      }
    }
    final atTop =
        Directory(p.join(dir.path, '.git')).existsSync() ||
        File(p.join(dir.path, '.git')).existsSync();
    if (atTop ||
        dir.parent.path == dir.path ||
        dir.path != project.root.path &&
            !p.isWithin(dir.path, project.root.path)) {
      return null;
    }
  }
}

/// `waive:` in health_check.yaml: a list of ids, or of {id, reason}.
Map<String, String> _projectWaivers(FlutterProject project, CheckContext ctx) {
  final f = project.file('health_check.yaml');
  if (!f.existsSync()) return {};
  final Object? yaml;
  try {
    yaml = loadYaml(f.readAsStringSync());
  } on YamlException catch (e) {
    ctx.notes.add(
      'health_check.yaml could not be read (${e.message}); no waivers applied.',
    );
    return {};
  }
  final list = yaml is YamlMap ? yaml['waive'] : null;
  if (list is! YamlList) return {};
  return {
    for (final w in list)
      if (w is YamlMap && w['id'] != null)
        '${w['id']}':
            '${w['reason'] ?? 'Accepted by the project (health_check.yaml).'}'
      else if (w is String)
        w: 'Accepted by the project (health_check.yaml).',
  };
}

/// For the CLI: whether [path] looks like a Flutter or Dart project.
bool isProject(String path) => File(p.join(path, 'pubspec.yaml')).existsSync();
