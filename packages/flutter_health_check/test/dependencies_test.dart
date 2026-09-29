import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  Map<String, String> app(String deps, Map<String, (String, String)> locked) =>
      {
        ...healthy(),
        'pubspec.yaml': pubspec.replaceFirst(
          '    sdk: flutter\n',
          '    sdk: flutter\n$deps',
        ),
        'pubspec.lock': lock(locked),
        'lib/main.dart': deps
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => "import 'package:${l.trim().split(':').first}/x.dart';")
            .join('\n'),
      };

  test(
    'discontinued, behind, unmaintained plugin, copyleft, advisories',
    () async {
      final registry = fakeRegistry(
        packages: {
          'old_http': {
            'latest': '1.0.0',
            'discontinued': true,
            'replacedBy': 'http',
          },
          'router': {'latest': '6.0.0'},
          'camera_x': {
            'latest': '0.3.0',
            'plugin': true,
            'published': '2023-02-01T00:00:00Z',
          },
          'pure_widgets': {
            'latest': '1.0.0',
            'published': '2022-01-01T00:00:00Z',
          },
          'gpl_thing': {
            'latest': '1.0.0',
            'tags': ['license:gpl-3.0'],
          },
        },
        advisories: {
          'router': [
            {
              'id': 'GHSA-aaaa-bbbb-cccc',
              'summary': 'Open redirect',
              'database_specific': {'severity': 'MODERATE'},
            },
          ],
          'deep_dep': [
            {
              'id': 'GHSA-dddd-eeee-ffff',
              'summary': 'Path traversal',
              'database_specific': {'severity': 'CRITICAL'},
            },
          ],
        },
      );
      final r = await check(
        project(
          app(
            '  old_http: ^1.0.0\n  router: ^3.0.0\n  camera_x: ^0.3.0\n  pure_widgets: ^1.0.0\n  gpl_thing: ^1.0.0\n',
            {
              'old_http': ('1.0.0', 'direct main'),
              'router': ('3.1.0', 'direct main'),
              'camera_x': ('0.3.0', 'direct main'),
              'pure_widgets': ('1.0.0', 'direct main'),
              'gpl_thing': ('1.0.0', 'direct main'),
              'deep_dep': ('2.0.0', 'transitive'),
            },
          ),
        ),
        client: registry,
      );
      expect(one(r, 'deps.discontinued').fix, contains('`http`'));
      expect(
        one(r, 'deps.breaking-behind').title,
        contains('3 breaking releases behind'),
      );
      expect(
        one(r, 'deps.unmaintained').detail,
        allOf(contains('camera_x'), isNot(contains('pure_widgets'))),
      );
      expect(one(r, 'deps.copyleft').title, contains('gpl-3.0'));
      final vulns = r.findings
          .where((f) => f.id == 'deps.vulnerability')
          .toList();
      expect(
        vulns.map((v) => v.severity),
        containsAll([Severity.medium, Severity.critical]),
      );
      expect(
        vulns.firstWhere((v) => v.title.contains('deep_dep')).fix,
        contains('arrives through another package'),
      );
      expect(r.dependencies.map((d) => d.name), contains('deep_dep'));
    },
  );

  test('OSV down: said so, not silently clean', () async {
    final r = await check(
      project(app('  router: ^3.0.0\n', {'router': ('3.1.0', 'direct main')})),
      client: fakeRegistry(
        packages: {
          'router': {'latest': '3.1.0'},
        },
        osvDown: true,
      ),
    );
    expect(
      r.notes.join(),
      contains('OSV advisory database could not be reached'),
    );
  });

  test('offline: rows without registry data, and a note', () async {
    final r = await check(
      project(app('  router: ^3.0.0\n', {'router': ('3.1.0', 'direct main')})),
    );
    expect(r.dependencies.single.latest, isNull);
    expect(r.notes.join(), contains('Network checks were off'));
  });

  test('Dart 2 constraint, overrides, floating git and outside path', () async {
    final r = await check(
      project({
        ...healthy(),
        'pubspec.yaml': '''
name: legacy
environment:
  sdk: ">=2.17.0 <3.0.0"
dependencies:
  flutter:
    sdk: flutter
  branchy:
    git: https://github.com/someone/branchy.git
  tagged:
    git:
      url: https://github.com/someone/tagged.git
      ref: v1.2.0
  sibling:
    path: ../../elsewhere/sibling
dependency_overrides:
  intl: 0.19.0
''',
      }),
    );
    expect(
      ids(r),
      containsAll(['deps.dart2-constraint', 'deps.overrides', 'deps.floating']),
    );
    expect(
      one(r, 'deps.floating').title,
      allOf(
        contains('branchy'),
        contains('sibling'),
        isNot(contains('tagged')),
      ),
    );
  });

  test('unused dependencies, minus the ones used without an import', () async {
    final r = await check(
      project({
        ...healthy(),
        'pubspec.yaml': '''
name: sample
environment:
  sdk: ^3.9.0
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  json_annotation: ^4.9.0
  intl: ^0.20.0
  lottie: ^3.0.0
  dio: ^5.0.0
  mime: ^2.0.0
flutter:
  generate: true
''',
        'lib/main.dart': "import 'package:dio/dio.dart';\n",
        // Generated code is still code: this is where slang-style packages are used.
        'lib/gen/strings.g.dart': "import 'package:mime/mime.dart';\n",
      }),
    );
    expect(
      one(r, 'deps.unused').title,
      '1 dependency is never imported: lottie',
    );
  });
}
