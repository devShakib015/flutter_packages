import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../context.dart';
import '../model.dart';
import '../pub_client.dart';

/// Locked packages against pub.dev and the OSV advisory database, and the
/// pubspec's own constraints, overrides and unpinned sources.
Future<List<Finding>> checkDependencies(CheckContext ctx) async {
  final project = ctx.project, pub = ctx.pub, now = ctx.now;
  final findings = <Finding>[];
  final notes = ctx.notes;
  final rows = ctx.dependencies;

  // The Dart SDK constraint: a Dart 2 floor means the app predates Dart 3 and
  // cannot be built with a current Flutter until it is migrated.
  final sdk = (project.pubspec['environment'] as YamlMap?)?['sdk']?.toString();
  if (sdk != null) ctx.facts['Dart SDK constraint'] = sdk;
  final floor = sdk == null
      ? null
      : RegExp(r'(?:\^|>=)\s*(\d+)\.').firstMatch(sdk);
  if (floor != null && int.parse(floor[1]!) < 3) {
    findings.add(
      Finding(
        id: 'deps.dart2-constraint',
        area: Area.dependencies,
        severity: Severity.high,
        title: 'The app is still on a Dart 2 SDK constraint ($sdk)',
        detail:
            'Current Flutter ships Dart 3. A project that allows only Dart 2 cannot be '
            'built with it, so every Flutter, plugin and security update is out of reach.',
        fix:
            'Raise the constraint to a Dart 3 range, fix the null-safety and language '
            'changes the analyzer reports, then upgrade dependencies.',
        locations: ['pubspec.yaml'],
      ),
    );
  }

  final overrides = project.pubspec['dependency_overrides'] as YamlMap?;
  if (overrides != null && overrides.isNotEmpty) {
    findings.add(
      Finding(
        id: 'deps.overrides',
        area: Area.dependencies,
        severity: Severity.medium,
        title:
            '${overrides.length} dependency override${overrides.length == 1 ? '' : 's'}: '
            '${overrides.keys.join(', ')}',
        detail:
            'Overrides force a version that the resolver would otherwise refuse. They hide '
            'real incompatibilities and tend to outlive the problem they worked around.',
        fix:
            'For each override, check whether the conflict still exists; remove it or '
            'write down why it stays.',
        locations: ['pubspec.yaml'],
      ),
    );
  }

  // Git dependencies that follow a branch, and path dependencies outside the
  // repository: builds that depend on something no lockfile pins.
  final declared = <String, Object?>{
    ...?(project.pubspec['dependencies'] as YamlMap?)?.cast<String, Object?>(),
    ...?(project.pubspec['dev_dependencies'] as YamlMap?)
        ?.cast<String, Object?>(),
  };
  final repo =
      _repositoryRoot(project.root.path) ?? project.resolutionRoot.path;
  final floating = <String>[];
  for (final e in declared.entries) {
    final spec = e.value;
    if (spec is! YamlMap) continue;
    final git = spec['git'];
    if (git != null) {
      final ref = git is YamlMap ? git['ref']?.toString() : null;
      if (ref == null) floating.add('${e.key} (git, no ref)');
    } else if (spec['path'] != null) {
      final target = p.normalize(
        p.join(project.root.path, spec['path'].toString()),
      );
      if (!p.isWithin(repo, target)) {
        floating.add('${e.key} (path outside the repository)');
      }
    }
  }
  if (floating.isNotEmpty) {
    findings.add(
      Finding(
        id: 'deps.floating',
        area: Area.dependencies,
        severity: Severity.low,
        title:
            '${floating.length} dependenc${floating.length == 1 ? 'y' : 'ies'} not pinned to a '
            'version: ${floating.join(', ')}',
        detail:
            'A git dependency without a ref follows a branch, and a path outside the '
            'repository only exists on one machine, so two builds of the same commit can differ.',
        fix:
            'Pin git dependencies to a tag or commit (`ref:`), and bring outside paths into the '
            'repository or publish them.',
        locations: ['pubspec.yaml'],
      ),
    );
  }

  final locked = project.locked;
  if (locked.isEmpty) {
    notes.add(
      'No pubspec.lock, so locked versions, updates and advisories were not '
      'checked. Run `flutter pub get` and commit the lockfile.',
    );
    return findings;
  }

  final direct = locked.values.where((l) => l.isDirect && l.onPubDev).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  ctx.facts['Packages'] =
      '${locked.values.where((l) => l.isDirect).length} direct, '
      '${locked.values.where((l) => !l.isDirect).length} transitive';

  if (pub == null) {
    notes.add(
      'Network checks were off: no update, maintenance or advisory data.',
    );
    rows.addAll(
      direct.map(
        (l) =>
            DependencyRow(name: l.name, kind: l.dependency, locked: l.version),
      ),
    );
    return findings;
  }

  final infos = await pub.infos(direct.map((l) => l.name));
  var vulns = <String, List<Vulnerability>>{};
  try {
    vulns = await pub.vulnerabilities({
      for (final l in locked.values)
        if (l.onPubDev) l.name: l.version,
    });
  } on StateError catch (e) {
    notes.add(
      'The OSV advisory database could not be reached (${e.message}), so known '
      'vulnerabilities were not checked.',
    );
  }

  final oneMajor = <String>[];
  final stale = <String>[];
  for (final l in direct) {
    final info = infos[l.name];
    final row = DependencyRow(
      name: l.name,
      kind: l.dependency,
      locked: l.version,
      latest: info?.latest,
      published: info?.published,
      points: info?.points,
      maxPoints: info?.maxPoints,
      discontinued: info?.discontinued ?? false,
      vulnerabilities: [
        for (final v in vulns[l.name] ?? const <Vulnerability>[]) v.id,
      ],
    );
    rows.add(row);
    if (info == null) continue;

    if (info.discontinued) {
      findings.add(
        Finding(
          id: 'deps.discontinued',
          area: Area.dependencies,
          severity: Severity.high,
          title: '`${l.name}` is discontinued',
          detail:
              'Its author has stopped maintaining it, so it will not be fixed for new '
              'Flutter, Android or iOS releases.',
          fix: info.replacedBy != null
              ? 'Move to `${info.replacedBy}`, which the author names as the replacement.'
              : 'Find a maintained replacement before the next platform upgrade breaks it.',
          locations: ['pubspec.yaml'],
        ),
      );
    }

    final behind = row.majorsBehind;
    if (behind != null && behind >= 2) {
      findings.add(
        Finding(
          id: 'deps.breaking-behind',
          area: Area.dependencies,
          severity: Severity.medium,
          title:
              '`${l.name}` is $behind breaking releases behind (${l.version} → ${info.latest})',
          detail:
              'Each breaking release (a new major version, or a new minor before 1.0) can need '
              'code changes. The further behind, the bigger the eventual upgrade, and fixes only '
              'land on the latest line.',
          fix: 'Read the changelog for each one and upgrade a step at a time.',
          locations: ['pubspec.lock'],
        ),
      );
    } else if (behind == 1) {
      oneMajor.add('${l.name} ${l.version} → ${info.latest}');
    }

    final published = info.published;
    if (!info.discontinued &&
        info.isPlugin &&
        l.dependency == 'direct main' &&
        published != null &&
        now.difference(published).inDays > 730) {
      stale.add(
        '${l.name} (last release ${published.year}-'
        '${published.month.toString().padLeft(2, '0')})',
      );
    }

    final copyleft = info.licenses.where(
      (x) => RegExp(r'^(a?gpl|lgpl)').hasMatch(x.toLowerCase()),
    );
    if (l.dependency == 'direct main' && copyleft.isNotEmpty) {
      findings.add(
        Finding(
          id: 'deps.copyleft',
          area: Area.dependencies,
          severity: Severity.medium,
          title:
              '`${l.name}` is under a copyleft licence (${copyleft.join(', ')})',
          detail:
              'GPL-family licences can oblige you to publish your own source when you '
              'distribute the app. That is rarely what a commercial app wants.',
          fix: 'Have the licence reviewed, or replace the package.',
          locations: ['pubspec.yaml'],
        ),
      );
    }
  }

  if (oneMajor.isNotEmpty) {
    findings.add(
      Finding(
        id: 'deps.one-breaking-behind',
        area: Area.dependencies,
        severity: Severity.low,
        title:
            '${oneMajor.length} direct dependenc${oneMajor.length == 1 ? 'y is' : 'ies are'} '
            'one breaking release behind',
        detail: oneMajor.join('; '),
        fix:
            'Upgrade while the gap is one version; it gets harder with each release you skip.',
        locations: ['pubspec.lock'],
      ),
    );
  }
  if (stale.isNotEmpty) {
    findings.add(
      Finding(
        id: 'deps.unmaintained',
        area: Area.dependencies,
        severity: Severity.medium,
        title:
            '${stale.length} plugin${stale.length == 1 ? ' has' : 's have'} had no release in '
            'over two years',
        detail:
            '${stale.join('; ')}. Plugins carry Android and iOS code, so they are what breaks '
            'when the platforms or Flutter move, and nobody is releasing fixes for these.',
        fix:
            'Check each one still builds on current Flutter; plan replacements for any '
            'that touch platform code.',
        locations: ['pubspec.yaml'],
      ),
    );
  }

  // Advisories for anything in the lockfile, direct or not.
  for (final e in vulns.entries) {
    final l = locked[e.key]!;
    for (final v in e.value) {
      final sev = switch (v.severity?.toUpperCase()) {
        'CRITICAL' => Severity.critical,
        'HIGH' => Severity.high,
        'MODERATE' || 'MEDIUM' => Severity.medium,
        'LOW' => Severity.low,
        _ => Severity.high,
      };
      if (!l.isDirect) {
        rows.add(
          DependencyRow(
            name: l.name,
            kind: l.dependency,
            locked: l.version,
            vulnerabilities: [v.id],
          ),
        );
      }
      findings.add(
        Finding(
          id: 'deps.vulnerability',
          area: Area.dependencies,
          severity: sev,
          title: '`${l.name}` ${l.version} has a known vulnerability (${v.id})',
          detail: v.summary.isEmpty
              ? 'See the advisory for details.'
              : v.summary,
          fix:
              'Upgrade `${l.name}` to a version the advisory lists as fixed'
              '${l.isDirect ? '' : ' (it arrives through another package: upgrade that one, '
                        'or add a direct constraint)'}.',
          locations: ['https://osv.dev/vulnerability/${v.id}'],
        ),
      );
    }
  }

  return findings;
}

String? _repositoryRoot(String from) {
  for (var d = Directory(from); d.path != d.parent.path; d = d.parent) {
    if (Directory(p.join(d.path, '.git')).existsSync() ||
        File(p.join(d.path, '.git')).existsSync()) {
      return d.path;
    }
  }
  return null;
}
