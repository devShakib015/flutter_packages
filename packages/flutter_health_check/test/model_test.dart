import 'dart:io';

import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:flutter_health_check/src/facts.dart';
import 'package:flutter_health_check/src/text.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Finding finding(Area area, Severity severity) =>
    Finding(id: 'x', area: area, severity: severity, title: 't', detail: 'd');

Report report(List<Finding> findings, {Set<Area> skipped = const {}}) => Report(
  projectName: 'p',
  generated: now,
  findings: findings,
  dependencies: const [],
  facts: ProjectFacts(),
  notes: const [],
  skipped: skipped,
);

void main() {
  group('breaking releases behind', () {
    int? behind(String locked, String latest) => DependencyRow(
      name: 'x',
      kind: 'direct main',
      locked: locked,
      latest: latest,
    ).majorsBehind;

    test('counts majors after 1.0', () => expect(behind('2.3.0', '5.0.1'), 3));
    test(
      'counts minors before 1.0',
      () => expect(behind('0.6.4+3', '0.8.0'), 2),
    );
    test(
      'counts every major when crossing 1.0',
      () => expect(behind('0.9.2', '3.1.0'), 3),
    );
    test('is zero when current', () => expect(behind('1.4.0', '1.9.0'), 0));
  });

  test('--version says what the pubspec says', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      RegExp(r'^version: (\S+)$', multiLine: true).firstMatch(pubspec)![1],
      toolVersion,
    );
  });

  test('store rules change on purpose, with their sources', () {
    expect(StoreRules.playTargetSdk, 36);
    expect(StoreRules.playTargetSdkSince, '31 August 2026');
    expect(StoreRules.playExistingAppFloor, 35);
    expect(StoreRules.appStoreSdk, 'Xcode 26 with the iOS 26 SDK');
    expect([
      StoreRules.playSource,
      StoreRules.appStoreSource,
      StoreRules.sceneSource,
    ], everyElement(startsWith('https://')));
  });

  test('versions compare numerically', () {
    expect(compareVersions('8.14', '8.9'), 1);
    expect(compareVersions('8.14', '8.14.0'), 0);
    expect(compareVersions('1.8.22', '1.9'), -1);
    expect(compareVersions('9.3.1', '9.1.0'), 1);
  });

  group('scores', () {
    test('lose points per finding', () {
      final r = report([
        finding(Area.code, Severity.medium),
        finding(Area.code, Severity.low),
      ]);
      expect(r.scoreFor(Area.code), 89);
      expect(r.scoreFor(Area.assets), 100);
    });

    test('a critical fails its area', () {
      final r = report([finding(Area.security, Severity.critical)]);
      expect(r.scoreFor(Area.security), 39);
      expect(Report.grade(r.scoreFor(Area.security)), 'F');
    });

    test('a high caps its area at C', () {
      expect(
        report([finding(Area.android, Severity.high)]).scoreFor(Area.android),
        74,
      );
    });

    test('one critical caps the whole report at D, however clean the rest', () {
      final r = report([finding(Area.security, Severity.critical)]);
      expect(r.overall, 59);
      expect(Report.grade(r.overall), 'D');
    });

    test('unchecked areas are left out, not scored 100', () {
      final r = report(
        [finding(Area.android, Severity.medium)],
        skipped: {Area.ios, Area.assets},
      );
      expect(r.scoredAreas, isNot(contains(Area.ios)));
      expect(r.overall, ((92 + 100 * 4) / 5).round());
    });
  });

  group('text helpers', () {
    test('comments go, strings and offsets stay', () {
      const code = 'a = "https://x" // gone\n/* also\ngone */ b';
      final out = stripComments(code);
      expect(out.length, code.length);
      expect(out, contains('"https://x"'));
      expect(out, isNot(contains('gone')));
      expect(out.split('\n').length, 3);
    });

    test('block finds the balanced body', () {
      const code = 'buildTypes { release { a { b } } debug { c } }';
      final types = block(code, RegExp(r'buildTypes\s*'))!;
      final release = block(code, RegExp(r'release\s*'), types.$1, types.$2)!;
      expect(code.substring(release.$1, release.$2).trim(), 'a { b }');
    });

    test('plist with attributes, nesting and arrays', () {
      final value =
          parsePlist(
                plist(
                  '<key>List</key><array><string>a</string><integer>2</integer></array>',
                ),
              )
              as Map<String, Object?>;
      expect(value['LSRequiresIPhoneOS'], true);
      expect(value['List'], ['a', 2]);
      expect(
        (value['UIApplicationSceneManifest']
            as Map)['UIApplicationSupportsMultipleScenes'],
        false,
      );
    });
  });
}
