import 'dart:convert';
import 'dart:io';

import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('tests and CI', () {
    test('no tests at all', () async {
      final r = await check(project(healthy()..remove('test/app_test.dart')));
      expect(one(r, 'testing.none').title, 'No tests');
    });

    test('only the template counter test', () async {
      final r = await check(
        project({
          ...healthy()..remove('test/app_test.dart'),
          'test/widget_test.dart':
              "void main() { testWidgets('Counter increments smoke test', (t) async {}); }",
        }),
      );
      expect(one(r, 'testing.none').title, contains('template counter test'));
    });

    test('thin coverage', () async {
      final r = await check(
        project({
          ...healthy(),
          for (var i = 0; i < 25; i++) 'lib/src/file_$i.dart': 'class C$i {}\n',
        }),
      );
      expect(
        one(r, 'testing.thin').title,
        'Thin coverage: 1 test case for 26 source files',
      );
    });

    test('no CI, and CI that never runs the tests', () async {
      final none = await check(
        project(healthy()..remove('.github/workflows/ci.yaml')),
      );
      expect(ids(none), contains('testing.no-ci'));
      final skips = await check(
        project({
          ...healthy(),
          '.github/workflows/ci.yaml': 'steps:\n  - run: flutter build apk\n',
        }),
      );
      expect(ids(skips), contains('testing.ci-skips-tests'));
      final codemagic = await check(
        project({
          ...healthy()..remove('.github/workflows/ci.yaml'),
          'codemagic.yaml': 'scripts:\n  - flutter test\n',
        }),
      );
      expect(codemagic.facts.values['CI'], 'Codemagic');
      expect(ids(codemagic), isEmpty);
    });
  });

  group('code', () {
    test('no lints, and long files', () async {
      final r = await check(
        project({
          ...healthy()..remove('analysis_options.yaml'),
          'lib/giant.dart': List.filled(900, '// line').join('\n'),
        }),
      );
      expect(ids(r), containsAll(['code.no-lints', 'code.large-files']));
      expect(
        one(r, 'code.large-files').detail,
        contains('lib/giant.dart (900)'),
      );
    });
  });

  group('assets', () {
    test(
      'heavy images, big files, unused files; interpolated paths count as used',
      () async {
        final r = await check(
          project({
            ...healthy(),
            'pubspec.yaml':
                '$pubspec\nflutter:\n  assets:\n    - assets/images/\n    - assets/flags/\n    - assets/bin/server\n',
            'assets/images/hero.png': 'x' * (600 * 1024),
            'assets/images/unused.png': 'x',
            'assets/flags/bd.png': 'x',
            'assets/bin/server': 'x' * (6 * 1024 * 1024),
            'lib/main.dart':
                "final hero = 'assets/images/hero.png'; String flag(String c) => 'assets/flags/\$c.png'; const s = 'assets/bin/server';",
          }),
        );
        expect(
          one(r, 'assets.heavy-images').title,
          contains('1 image over 500 KB'),
        );
        expect(
          one(r, 'assets.large-files').title,
          'assets/bin/server adds 6.0 MB to every install',
        );
        expect(
          one(r, 'assets.unused').detail,
          allOf(
            contains('assets/images/unused.png'),
            isNot(contains('bd.png')),
          ),
        );
      },
    );
  });

  group('project', () {
    test(
      'a pinned Flutter that differs from the one checking is said out loud',
      () async {
        final r = await check(
          project({...healthy(), '.fvmrc': '{"flutter": "3.24.5"}'}),
        );
        expect(
          r.facts.values['Flutter pinned by the project'],
          '3.24.5 (.fvmrc)',
        );
        expect(r.notes.join(), contains('pins Flutter 3.24.5'));
      },
    );

    test(
      'a pin at the repository root counts for an app in a subfolder',
      () async {
        final repo = project({
          '.fvmrc': '{"flutter": "3.41.9"}',
          for (final e in healthy().entries) 'app/${e.key}': e.value,
        });
        git(repo, ['init', '-q']);
        final r = await check(Directory(p.join(repo.path, 'app')));
        expect(
          r.facts.values['Flutter pinned by the project'],
          '3.41.9 (../.fvmrc)',
        );
      },
    );

    test(
      'waivers in health_check.yaml leave the score but stay in the report',
      () async {
        final r = await check(
          project({
            ...healthy()..remove('.github/workflows/ci.yaml'),
            'health_check.yaml':
                'waive:\n  - id: testing.no-ci\n    reason: Builds run on the agency\'s Jenkins.\n',
          }),
        );
        expect(ids(r), isEmpty);
        expect(r.waived.single.$2, contains('Jenkins'));
        expect(toMarkdown(r), contains('Accepted by the project'));
      },
    );

    test('workspace member reads the root lockfile', () async {
      final root = project({
        'pubspec.yaml':
            'name: root\nenvironment:\n  sdk: ^3.9.0\nworkspace:\n  - app\n',
        'pubspec.lock': lock({'router': ('3.1.0', 'direct main')}),
        for (final e in healthy().entries) 'app/${e.key}': e.value,
        'app/pubspec.yaml': '$pubspec\nresolution: workspace\n'.replaceFirst(
          '    sdk: flutter\n',
          '    sdk: flutter\n  router: ^3.0.0\n',
        ),
      });
      final r = await check(Directory(p.join(root.path, 'app')));
      expect(r.dependencies.single.name, 'router');
      expect(r.notes.join(), isNot(contains('No pubspec.lock')));
    });
  });

  group('report', () {
    test('markdown, html and json agree; html escapes', () async {
      final r = await check(
        project({
          ...healthy(),
          'lib/giant.dart': List.filled(900, '<script>').join('\n'),
        }),
      );
      final md = toMarkdown(r), html = toHtml(r);
      final json = jsonDecode(toJson(r)) as Map<String, Object?>;
      expect(md, contains('Code health'));
      expect(html, isNot(contains('<script>')));
      expect(json['overall'], r.overall);
      expect(
        (json['findings'] as List).map((f) => (f as Map)['id']),
        ids(r).toList(),
      );
    });

    test('skipped areas say so', () async {
      final r = await check(
        project(healthy()..removeWhere((k, _) => k.startsWith('ios/'))),
      );
      expect(
        toMarkdown(r),
        contains('| iOS & App Store | – | – | not checked |'),
      );
      expect(toHtml(r), contains('not checked'));
    });
  });
}
