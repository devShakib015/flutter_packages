import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../model.dart';

const _ci = <String, List<String>>{
  'GitHub Actions': ['.github/workflows'],
  'Codemagic': ['codemagic.yaml', 'codemagic.yml'],
  'Bitrise': ['bitrise.yml', 'bitrise.yaml'],
  'GitLab CI': ['.gitlab-ci.yml'],
  'CircleCI': ['.circleci/config.yml'],
  'Azure Pipelines': ['azure-pipelines.yml'],
  'Bitbucket Pipelines': ['bitbucket-pipelines.yml'],
  'Jenkins': ['Jenkinsfile'],
  'fastlane': [
    'fastlane/Fastfile',
    'android/fastlane/Fastfile',
    'ios/fastlane/Fastfile',
  ],
};

/// Tests, and whether a CI pipeline builds the app and runs them.
List<Finding> checkTesting(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];

  final testFiles = [
    ...project.dartFiles('test'),
    ...project.dartFiles('integration_test'),
  ];
  final caseRe = RegExp(
    r'\b(?:test|testWidgets|blocTest|patrolTest|testGoldens|goldenTest)\s*(?:<[^>()]*>)?\s*\(',
  );
  var cases = 0, integration = 0;
  var onlyTemplate = testFiles.isNotEmpty;
  for (final f in testFiles) {
    final text = f.readAsStringSync();
    final n = caseRe.allMatches(text).length;
    cases += n;
    if (project.rel(f.path).startsWith('integration_test')) integration += n;
    if (!text.contains('Counter increments smoke test')) onlyTemplate = false;
  }
  final libFiles = project.dartFiles('lib').length;
  ctx.facts['Tests'] =
      '$cases test case${cases == 1 ? '' : 's'} in ${testFiles.length} '
      'file${testFiles.length == 1 ? '' : 's'}'
      '${integration > 0 ? ' ($integration integration)' : ''}';

  if (cases == 0 || onlyTemplate) {
    findings.add(
      Finding(
        id: 'testing.none',
        area: Area.testing,
        severity: Severity.high,
        title: onlyTemplate
            ? 'The only test is Flutter\'s template counter test'
            : 'No tests',
        detail:
            '${onlyTemplate ? 'It tests the counter app the project started from, so it most likely fails, and nothing else is tested. ' : ''}'
            'Every release is verified by hand, so regressions reach users, and nobody can refactor '
            'safely.',
        fix:
            'Start where bugs cost most: unit tests for the business logic (pricing, auth '
            'state, data parsing), then widget tests for the main flows. Run them in CI.',
        locations: [if (onlyTemplate) 'test/widget_test.dart' else 'test/'],
      ),
    );
  } else if (libFiles >= 20 && cases < libFiles / 5) {
    findings.add(
      Finding(
        id: 'testing.thin',
        area: Area.testing,
        severity: Severity.medium,
        title:
            'Thin coverage: $cases test case${cases == 1 ? '' : 's'} for $libFiles source files',
        detail:
            'Most of the code has no test, so a change anywhere can break something nobody '
            'checks.',
        fix:
            'Measure with `flutter test --coverage`, then cover the logic that handles money, '
            'accounts and user data first.',
        locations: const ['test/'],
      ),
    );
  }

  // CI can live at the repository root when the app is in a subfolder.
  final roots = <Directory>[project.root];
  var dir = project.root;
  for (
    var i = 0;
    i < 4 && !Directory(p.join(dir.path, '.git')).existsSync();
    i++
  ) {
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    roots.add(dir = parent);
  }
  final found = <String, List<File>>{};
  for (final root in roots) {
    for (final MapEntry(key: name, value: paths) in _ci.entries) {
      for (final rel in paths) {
        final path = p.join(root.path, rel);
        if (Directory(path).existsSync()) {
          final ymls = Directory(path)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
              .toList();
          if (ymls.isNotEmpty) found.putIfAbsent(name, () => []).addAll(ymls);
        } else if (File(path).existsSync()) {
          found.putIfAbsent(name, () => []).add(File(path));
        }
      }
    }
  }
  ctx.facts['CI'] = found.isEmpty ? 'none found' : found.keys.join(', ');
  if (found.isEmpty) {
    findings.add(
      Finding(
        id: 'testing.no-ci',
        area: Area.testing,
        severity: Severity.medium,
        title: 'No CI configuration',
        detail:
            'Nothing builds the app or runs the tests on each change, so a broken build is '
            'found by whoever builds next, often on release day.',
        fix:
            'Add a workflow that runs `flutter analyze`, `flutter test` and a release build on '
            'every pull request (GitHub Actions and Codemagic both have free tiers).',
        locations: const [],
      ),
    );
  } else if (cases > 0) {
    final runsTests = found.values
        .expand((f) => f)
        .any(
          (f) => RegExp(
            r'flutter\s+test|melos\s+(?:run\s+)?test|very_good\s+test|dart\s+test|flutter-test@|flutter_test\b',
          ).hasMatch(f.readAsStringSync()),
        );
    if (!runsTests) {
      findings.add(
        Finding(
          id: 'testing.ci-skips-tests',
          area: Area.testing,
          severity: Severity.low,
          title: 'CI does not run the tests',
          detail:
              'The pipeline exists but no step runs `flutter test`, so the tests only run '
              'when someone remembers.',
          fix: 'Add `flutter test` before the build step.',
          locations: [
            for (final f in found.values.expand((f) => f)) project.rel(f.path),
          ],
        ),
      );
    }
  }
  return findings;
}
