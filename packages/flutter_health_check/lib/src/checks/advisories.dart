import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../facts.dart';
import '../model.dart';
import '../project.dart';
import '../text.dart';
import 'testing.dart';

const _compromised =
    'eMudhra intermediate certificate authorities were compromised, so whoever holds their keys '
    'can forge HTTPS certificates that look legitimate.';

/// The compiled-in root certificates that trust eMudhra, which OSV does not
/// list and an operating system update cannot reach.
List<Finding> checkAdvisories(CheckContext ctx) => [
  ..._flutter(ctx),
  ..._firestore(ctx),
  ..._appDistribution(ctx),
];

/// Whether Flutter [version] has the fix: 3.47.8 on stable, 3.50.0-0.2.pre on
/// beta. [compareVersions] drops the pre-release part, so beta compares it here.
bool flutterHasEmudhraFix(String version) {
  final parts = version.split('-');
  if (parts.length == 1) {
    return compareVersions(version, EmudhraAdvisory.flutterFixed) >= 0;
  }
  final fixed = EmudhraAdvisory.flutterBetaFixed.split('-');
  final base = compareVersions(parts[0], fixed[0]);
  return base != 0 ? base > 0 : compareVersions(parts[1], fixed[1]) >= 0;
}

/// Whether cloud_firestore [version] has the fix on the platforms the app
/// builds for: 6.10.1 fixed iOS and macOS, and 6.10.2 added Windows.
bool firestoreHasEmudhraFix(String version, {required bool windows}) {
  if (compareVersions(version, '7.0.0') > 0) return true;
  if (compareVersions(version, '7.0.0') == 0) return false;
  if (compareVersions(version, EmudhraAdvisory.firestore6Fixed) >= 0) {
    return true;
  }
  return version == '6.10.1' && !windows;
}

// `flutter-version: 3.47.5`, `FLUTTER_VERSION: "3.47.5"`, and Codemagic's
// `flutter: 3.47.5`. A channel or `3.x` floats, so it is not a pin.
final _ciPin = RegExp(
  r'''^[ \t]*-?[ \t]*(?:flutter[-_]version|flutter)[ \t]*[:=][ \t]*["']?(\d+\.\d+\.\d+[\w.+-]*)''',
  multiLine: true,
  caseSensitive: false,
);

/// CI config, plus the composite actions workflows hand the Flutter setup to.
Iterable<File> _ciFiles(FlutterProject project) sync* {
  for (final files in ciConfigs(project).values) {
    yield* files;
  }
  for (final root in repositoryRoots(project)) {
    final actions = Directory(p.join(root.path, '.github/actions'));
    if (!actions.existsSync()) continue;
    for (final dir in actions.listSync().whereType<Directory>()) {
      for (final name in ['action.yml', 'action.yaml']) {
        final f = File(p.join(dir.path, name));
        if (f.existsSync()) yield f;
      }
    }
  }
}

/// Flutter as a git submodule: pinned, at a commit this check does not read.
bool _flutterSubmodule(FlutterProject project) =>
    repositoryRoots(project).any((root) {
      final f = File(p.join(root.path, '.gitmodules'));
      return f.existsSync() &&
          RegExp(
            r'url\s*=.*flutter/flutter(\.git)?\s*$',
            multiLine: true,
          ).hasMatch(f.readAsStringSync());
    });

List<Finding> _flutter(CheckContext ctx) {
  final project = ctx.project;
  final android = project.dir('android').existsSync();
  final windows = project.dir('windows').existsSync();
  final linux = project.dir('linux').existsSync();
  if (!android && !windows && !linux) return const [];

  // What builds the release: what the project pins, or this machine's Flutter.
  final pins = <(String, String)>[
    if (ctx.pinnedFlutter case final v? when RegExp(r'^\d+\.\d+').hasMatch(v))
      (v, ctx.pinnedFlutterAt ?? ''),
    for (final f in _ciFiles(project))
      for (final m in _ciPin.allMatches(f.readAsStringSync()))
        (m[1]!, '${project.rel(f.path)}:${lineOf(m.input, m.start)}'),
  ];
  final installed = ctx.defaults.flutterVersion;
  if (pins.isEmpty && (installed == null || _flutterSubmodule(project))) {
    ctx.notes.add(
      'Could not tell which Flutter builds this app, so whether it has Flutter '
      '${EmudhraAdvisory.flutterFixed}\'s fix for the eMudhra certificates was not checked.',
    );
    return const [];
  }
  final behind = [
    for (final pin in pins.isEmpty ? [(installed!, '')] : pins)
      if (!flutterHasEmudhraFix(pin.$1)) pin,
  ]..sort((a, b) => compareVersions(a.$1, b.$1));
  if (behind.isEmpty) return const [];

  const fixed = EmudhraAdvisory.flutterFixed;
  final platforms = [
    if (android) 'Android',
    if (windows) 'Windows',
  ].join(' and ');
  const linuxScope =
      'wherever `ca-certificates` has not been updated, as in static containers';
  return [
    Finding(
      id: 'security.emudhra-flutter',
      area: Area.security,
      // On Linux the system's store protects most machines, and with no pin
      // this machine's Flutter may not be the one that builds the release.
      severity: platforms.isEmpty || pins.isEmpty
          ? Severity.medium
          : Severity.high,
      title:
          'Flutter ${behind.first.$1} trusts the compromised eMudhra certificates',
      detail:
          '$_compromised '
          '${platforms.isEmpty ? 'On Linux, Flutter below $fixed trusts them $linuxScope.' : '`dart:io` uses root certificates compiled into the app and does not read the '
                    'operating system\'s blocklist, so on $platforms every build from Flutter '
                    'below $fixed keeps trusting them.${linux ? ' On Linux, it does so $linuxScope.' : ''}'}'
          '${pins.isEmpty ? ' Nothing in the project pins a Flutter, so this is the one on this machine, which may not be the one that builds your releases.' : ''}'
          ' ${EmudhraAdvisory.dartSource}',
      fix:
          'Move to Flutter $fixed or later (${EmudhraAdvisory.flutterBetaFixed} on beta), rebuild '
          'and release, and ask users to update: builds already installed stay exposed.',
      locations: [
        for (final pin in behind)
          if (pin.$2.isNotEmpty) pin.$2,
      ],
    ),
  ];
}

List<Finding> _firestore(CheckContext ctx) {
  final project = ctx.project;
  final locked = project.locked['cloud_firestore'];
  if (locked == null || !locked.onPubDev || locked.dependency == 'direct dev') {
    return const [];
  }
  final windows = project.dir('windows').existsSync();
  final apple =
      project.dir('ios').existsSync() || project.dir('macos').existsSync();
  if (!apple && !windows) return const [];
  if (firestoreHasEmudhraFix(locked.version, windows: windows)) {
    return const [];
  }
  return [
    Finding(
      id: 'security.emudhra-firestore',
      area: Area.security,
      severity: Severity.high,
      title:
          'cloud_firestore ${locked.version} trusts the compromised eMudhra certificates',
      detail:
          '$_compromised Firestore carries its own root certificates on iOS, macOS and Windows, '
          'compiled into the app, so neither an operating system update nor a server change '
          'reaches builds already installed. Firebase lists 7.0.0 and earlier as affected, '
          'apart from 6.10.1 (iOS and macOS only) and 6.10.2. Firestore on Android and the web '
          'is not. ${EmudhraAdvisory.firebaseSource}',
      fix: _firestoreFix(project, locked),
      locations: const ['pubspec.yaml'],
    ),
  ];
}

/// FlutterFire's packages and the ones built on them, by name: firebase_*,
/// cloud_firestore, cloud_functions, fake_cloud_firestore, geoflutterfire.
final _flutterFire = RegExp(
  r'firebase|firestore|flutterfire|^cloud_functions$',
);

/// How to reach a fixed cloud_firestore while moving as little as possible.
///
/// Measured on a real app's lockfile (cloud_firestore 6.6.0): naming the
/// packages in `pub upgrade` changed nothing, because the solver keeps what is
/// locked; raising the two floors first moved 10 packages and reached 6.10.2.
/// A plain `pub upgrade` gets there too, by moving everything (118 there).
String _firestoreFix(FlutterProject project, LockedPackage firestore) {
  final locked = project.locked;
  final direct = [
    for (final pkg in locked.values)
      if (pkg.isDirect && pkg.onPubDev && _flutterFire.hasMatch(pkg.name))
        pkg.name,
  ]..sort();
  final pods = [
    for (final os in ['ios', 'macos'])
      if (project.file('$os/Podfile.lock').existsSync()) '$os/',
  ];
  final podStep = pods.isEmpty
      ? ''
      : ' In ${pods.join(' and ')}, run `pod update Firebase` too, because '
            'Podfile.lock still pins the old Firebase SDK.';
  const release = ' Then release and ask users to update.';
  final version = firestore.version;

  // Below 6, the fix is a major version or two away, and so is everything
  // that moves with it. --major-versions only takes direct dependencies.
  if (compareVersions(version, '6.0.0') < 0) {
    final names = direct.isEmpty
        ? 'cloud_firestore firebase_core'
        : direct.join(' ');
    return 'cloud_firestore $version is a major version behind the fix, so move the '
        'FlutterFire packages to their current majors together: '
        '`flutter pub upgrade --major-versions $names` rewrites their constraints and '
        'reaches ${EmudhraAdvisory.firestoreFixed} with firebase_core 5.1. Expect breaking '
        'changes from the majors in between.$podStep$release';
  }

  final seven = version.startsWith('7.');
  final floors = <String, String>{
    'cloud_firestore': seven
        ? EmudhraAdvisory.firestoreFixed
        : EmudhraAdvisory.firestore6Fixed,
    'firebase_core': seven ? '5.1.0' : '4.15.2',
    // 4.1.1 no longer compiles against cloud_firestore 6.10.2
    // (MockWriteBatch.update); 4.2.0 does. Naming it doesn't move it.
    'fake_cloud_firestore': '4.2.0',
  };
  final raise = [
    for (final MapEntry(key: name, value: floor) in floors.entries)
      if (locked[name] case final pkg?
          when pkg.isDirect && compareVersions(pkg.version, floor) < 0)
        '`$name` to `^$floor`',
  ];
  final names = {'cloud_firestore', 'firebase_core', ...direct}.toList()
    ..sort();
  final upgrade = '`flutter pub upgrade ${names.join(' ')}`';
  final how = firestore.isDirect
      ? 'In pubspec.yaml raise ${_and(raise)}, then run $upgrade. Raising the floors is '
            'what moves them: named alone, pub keeps what is locked. This moves the '
            'FlutterFire packages together and little else.'
      : 'cloud_firestore comes in through another package, so add '
            '`cloud_firestore: ^${floors['cloud_firestore']}` to dependencies to set its '
            'floor${raise.isEmpty ? '' : ', raise ${_and(raise)}'}, then run $upgrade. If '
            'pub cannot resolve that, the package that pulls it in needs upgrading first.';
  return '$how$podStep$release';
}

String _and(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

final _appDistributionPlugin = RegExp(
  r'''(?:com\.google\.firebase\.appdistribution["'\s)]+version\s*\(?\s*["']|firebase-appdistribution-gradle:)(\d+\.\d+\.\d+)''',
);

List<Finding> _appDistribution(CheckContext ctx) {
  final project = ctx.project;
  for (final path in [
    'android/settings.gradle.kts',
    'android/settings.gradle',
    'android/build.gradle.kts',
    'android/build.gradle',
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
  ]) {
    final file = project.file(path);
    if (!file.existsSync()) continue;
    final code = stripComments(file.readAsStringSync());
    final m = _appDistributionPlugin.firstMatch(code);
    if (m == null) continue;
    final version = m[1]!;
    if (compareVersions(version, EmudhraAdvisory.appDistributionFixed) >= 0 ||
        version == '4.2.1' ||
        version == '3.2.1') {
      return const [];
    }
    return [
      Finding(
        id: 'security.emudhra-app-distribution',
        area: Area.security,
        severity: Severity.medium,
        title:
            'Firebase App Distribution plugin $version trusts the compromised eMudhra certificates',
        detail:
            '$_compromised The plugin carries its own root certificates and runs on the machine '
            'that uploads your builds. Firebase lists 5.3.0 and earlier as affected, apart from '
            '4.2.1 and 3.2.1. ${EmudhraAdvisory.firebaseSource}',
        fix:
            'Upgrade the plugin to ${EmudhraAdvisory.appDistributionFixed} or later. The app does '
            'not need redeploying for this one.',
        locations: [path],
      ),
    ];
  }
  return const [];
}
