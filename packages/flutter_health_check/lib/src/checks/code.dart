import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../context.dart';
import '../model.dart';

const _stateManagement = {
  'provider': 'Provider',
  'flutter_riverpod': 'Riverpod',
  'hooks_riverpod': 'Riverpod',
  'riverpod': 'Riverpod',
  'flutter_bloc': 'BLoC',
  'bloc': 'BLoC',
  'get': 'GetX',
  'mobx': 'MobX',
  'flutter_mobx': 'MobX',
  'flutter_redux': 'Redux',
  'redux': 'Redux',
  'stacked': 'Stacked',
  'signals': 'Signals',
  'signals_flutter': 'Signals',
};

/// Dependencies that are used without a Dart import: fonts, native-only
/// libraries, command-line tools and analyzer plugins.
bool _usedWithoutImport(String name) =>
    const {
      'flutter',
      'flutter_test',
      'flutter_localizations',
      'flutter_web_plugins',
      'cupertino_icons',
      'build_runner',
      'flutter_launcher_icons',
      'flutter_native_splash',
      'icons_launcher',
      'intl_utils',
      'lints',
      'flutter_lints',
      'very_good_analysis',
      'custom_lint',
      'msix',
      'rename',
      'change_app_package_name',
      'package_rename',
      'flutter_flavorizr',
      'sentry_dart_plugin',
      'dependency_validator',
      'melos',
      'import_sorter',
      'dart_code_metrics',
    }.contains(name) ||
    RegExp(
      r'_(annotation|generator|lint|lints|runner|flutter_libs|android|ios|web|macos|windows|linux|foundation)$',
    ).hasMatch(name);

/// Lint setup, `dart analyze` results, long files, and dependencies nothing
/// imports.
Future<List<Finding>> checkCode(CheckContext ctx) async {
  final project = ctx.project;
  final findings = <Finding>[];

  // Size, and where the weight is.
  final files = project.dartFiles('lib').toList();
  var lines = 0, todos = 0;
  final large = <(String, int)>[];
  final imports = <String>{};
  void collectImports(String text) {
    for (final m in RegExp(
      r'''(?:import|export)\s+['"]package:([\w]+)/''',
    ).allMatches(text)) {
      imports.add(m[1]!);
    }
  }

  // Generated code counts for imports: strings.g.dart is what uses slang.
  for (final sub in [
    'lib',
    'test',
    'integration_test',
    'bin',
    'tool',
    'test_driver',
  ]) {
    for (final f in project.files(
      sub: sub,
      where: (path) => path.endsWith('.dart'),
    )) {
      collectImports(f.readAsStringSync());
    }
  }
  for (final f in files) {
    final text = f.readAsStringSync();
    final n = '\n'.allMatches(text).length + 1;
    lines += n;
    todos += RegExp(r'//\s*(TODO|FIXME|HACK)\b').allMatches(text).length;
    if (n > 800) large.add((project.rel(f.path), n));
  }
  ctx.facts['Dart code (lib/)'] = '${files.length} files, $lines lines';
  if (todos > 0) ctx.facts['TODO / FIXME / HACK comments'] = '$todos';
  if (large.isNotEmpty) {
    large.sort((a, b) => b.$2.compareTo(a.$2));
    findings.add(
      Finding(
        id: 'code.large-files',
        area: Area.code,
        severity: Severity.low,
        title:
            '${large.length} file${large.length == 1 ? '' : 's'} over 800 lines',
        detail:
            '${large.take(5).map((e) => '${e.$1} (${e.$2})').join(', ')}. Files this long '
            'usually mix several jobs, which makes them hard to review and test in isolation.',
        fix:
            'Split along the seams that are already there: widgets, state, data access.',
        locations: [for (final e in large.take(5)) e.$1],
      ),
    );
  }

  final deps =
      (project.pubspec['dependencies'] as YamlMap?)?.keys
          .map((k) => '$k')
          .toSet() ??
      {};
  final approaches = {
    for (final d in deps)
      if (_stateManagement[d] != null) _stateManagement[d]!,
  };
  ctx.facts['State management'] = approaches.isEmpty
      ? 'none detected (setState / built-in)'
      : approaches.join(' + ');

  // Declared, never imported.
  final analysisOptions = project.file('analysis_options.yaml');
  final optionsText = analysisOptions.existsSync()
      ? analysisOptions.readAsStringSync()
      : '';
  // gen_l10n generates code that imports intl, outside lib/.
  final l10n =
      (project.pubspec['flutter'] as YamlMap?)?['generate'] == true ||
      project.file('l10n.yaml').existsSync();
  final unused = [
    for (final d in deps)
      if (!imports.contains(d) &&
          !_usedWithoutImport(d) &&
          !(d == 'intl' && l10n) &&
          !optionsText.contains('package:$d/') &&
          project.pubspec[d] ==
              null) // configured in pubspec, e.g. flutter_native_splash:
        d,
  ]..sort();
  if (unused.isNotEmpty) {
    findings.add(
      Finding(
        id: 'deps.unused',
        area: Area.dependencies,
        severity: Severity.low,
        title:
            '${unused.length} dependenc${unused.length == 1 ? 'y is' : 'ies are'} never imported: '
            '${unused.join(', ')}',
        detail:
            'No Dart file imports them. Unused packages still add native code, permissions '
            'and upgrade work.',
        fix:
            'Check each one is not used some other way (a font, native code, a build step), '
            'then remove it.',
        locations: ['pubspec.yaml'],
      ),
    );
  }

  // Lints.
  if (!analysisOptions.existsSync()) {
    findings.add(
      Finding(
        id: 'code.no-lints',
        area: Area.code,
        severity: Severity.medium,
        title: 'No analysis_options.yaml, so no lint rules',
        detail:
            'Without lints, the analyzer only reports errors; the common bug patterns '
            '(unawaited futures, BuildContext across async gaps, missing dispose) go unflagged.',
        fix:
            'Add flutter_lints (or very_good_analysis) and include it from analysis_options.yaml.',
        locations: ['analysis_options.yaml'],
      ),
    );
  } else {
    final include = RegExp(
      r'^include:\s*(?:\[\s*)?(\S+?)[\],]?\s*$',
      multiLine: true,
    ).firstMatch(optionsText)?[1];
    ctx.facts['Lint rules'] = include == null
        ? 'own rules only'
        : include.replaceAll(RegExp(r'''['"]'''), '');
  }

  if (ctx.analyze) findings.addAll(await _analyze(ctx));
  return findings;
}

Future<List<Finding>> _analyze(CheckContext ctx) async {
  final project = ctx.project;
  final resolved = project.packageConfig.existsSync();
  if (!resolved) {
    if (!ctx.pubGet) {
      ctx.notes.add(
        'Packages are not resolved (no .dart_tool), so `dart analyze` did not run. '
        'Run `flutter pub get` first, or pass --pub-get.',
      );
      return [];
    }
    final get = await Process.run(
      ctx.flutter,
      ['pub', 'get'],
      workingDirectory: project.root.path,
      runInShell: Platform.isWindows,
    );
    if (get.exitCode != 0) {
      final reason = '${get.stderr}'
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(3)
          .join(' ');
      ctx.notes.add(
        '`flutter pub get` failed, so `dart analyze` did not run: $reason',
      );
      return [];
    }
  }

  final ProcessResult r;
  try {
    r = await Process.run(
      ctx.dart,
      ['analyze', '--format=machine', '.'],
      workingDirectory: project.root.path,
      runInShell: Platform.isWindows,
    ).timeout(const Duration(minutes: 10));
  } on Exception catch (e) {
    ctx.notes.add('`dart analyze` could not run: $e');
    return [];
  }

  final errors = <String>[],
      warnings = <String>[],
      deprecated = <String, int>{};
  final warningCodes = <String, int>{};
  var infos = 0;
  final deprecatedAt = <String>[];
  for (final line in '${r.stderr}\n${r.stdout}'.split('\n')) {
    final parts = line.split('|');
    if (parts.length < 8) continue;
    final (severity, code, file, row, message) = (
      parts[0],
      parts[2].toLowerCase(),
      parts[3],
      parts[4],
      parts.sublist(7).join('|'),
    );
    final rel = p.isAbsolute(file) ? project.rel(file) : file;
    if (rel.startsWith('..') ||
        rel.startsWith('build/') ||
        rel.contains('.dart_tool')) {
      continue;
    }
    final at = '$rel:$row';
    if (code.startsWith('deprecated_member_use')) {
      final api = RegExp(r"^'([^']+)'").firstMatch(message)?[1] ?? code;
      deprecated[api] = (deprecated[api] ?? 0) + 1;
      if (deprecatedAt.length < 10) deprecatedAt.add(at);
      continue;
    }
    switch (severity) {
      case 'ERROR':
        errors.add('$at  $message');
      case 'WARNING':
        warnings.add(at);
        warningCodes[code] = (warningCodes[code] ?? 0) + 1;
      case 'INFO':
        infos++;
    }
  }
  final flutter = ctx.defaults.flutterVersion == null
      ? 'the installed Flutter'
      : 'Flutter ${ctx.defaults.flutterVersion}';
  ctx.facts['Analyzer (with $flutter)'] =
      '${errors.length} errors, ${warnings.length} warnings, '
      '${deprecated.values.fold(0, (a, b) => a + b)} deprecated API uses, $infos lint infos';

  final findings = <Finding>[];
  final pinned = ctx.pinnedFlutter;
  final upgradeOnly = ctx.checksAnUpgrade;
  if (errors.isNotEmpty) {
    findings.add(
      Finding(
        id: 'code.analyzer-errors',
        area: Area.code,
        severity: upgradeOnly ? Severity.high : Severity.critical,
        title:
            '`dart analyze` reports ${errors.length} error${errors.length == 1 ? '' : 's'} with $flutter',
        detail:
            'Errors are code that does not compile. '
            '${upgradeOnly ? 'The project pins Flutter $pinned, so these are what break when it upgrades. ' : ''}'
            'First ${errors.length < 5 ? errors.length : 5}: ${errors.take(5).join('; ')}',
        fix:
            'Fix these first; nothing else in this report can be verified on a build that fails.',
        locations: [for (final e in errors.take(20)) e.split('  ').first],
      ),
    );
  }
  if (warnings.isNotEmpty) {
    final top =
        (warningCodes.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5);
    findings.add(
      Finding(
        id: 'code.analyzer-warnings',
        area: Area.code,
        severity: Severity.medium,
        title:
            '${warnings.length} analyzer warning${warnings.length == 1 ? '' : 's'}',
        detail:
            'Warnings are likely bugs rather than style: dead code, unused results, invalid '
            'overrides, null checks that cannot fail. Most common: '
            '${top.map((e) => '${e.key} (${e.value})').join(', ')}.',
        fix: 'Work through them by code; most fixes are one line.',
        locations: warnings.take(20).toList(),
      ),
    );
  }
  if (deprecated.isNotEmpty) {
    final total = deprecated.values.fold(0, (a, b) => a + b);
    final top =
        (deprecated.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .take(6);
    findings.add(
      Finding(
        id: 'code.deprecated-apis',
        area: Area.code,
        severity: total > 50 ? Severity.medium : Severity.low,
        title: '$total use${total == 1 ? '' : 's'} of deprecated APIs',
        detail:
            'Deprecated APIs are removed in a later release, so each one is upgrade work '
            'waiting to happen. Most used: ${top.map((e) => '${e.key} (${e.value})').join(', ')}.',
        fix:
            'The analyzer message names the replacement for each; `dart fix --apply` handles '
            'many automatically.',
        locations: deprecatedAt,
      ),
    );
  }
  return findings;
}
