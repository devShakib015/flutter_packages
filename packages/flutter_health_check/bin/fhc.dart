import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'out',
      abbr: 'o',
      help: 'Where to write the report, without extension.',
      defaultsTo: 'health-report',
    )
    ..addMultiOption(
      'format',
      abbr: 'f',
      allowed: ['md', 'html', 'json'],
      defaultsTo: ['md', 'html'],
      help: 'Report formats to write.',
    )
    ..addFlag(
      'network',
      defaultsTo: true,
      help: 'Read pub.dev and the OSV advisory database.',
    )
    ..addFlag('analyze', defaultsTo: true, help: 'Run `dart analyze`.')
    ..addFlag(
      'pub-get',
      negatable: false,
      help:
          'Run `flutter pub get` first if packages are not resolved (writes .dart_tool).',
    )
    ..addMultiOption(
      'waive',
      help: 'Finding ids to report as accepted, e.g. android.debug-signing.',
    )
    ..addOption(
      'fail-on',
      allowed: ['critical', 'high', 'medium', 'low', 'never'],
      defaultsTo: 'never',
      help:
          'Exit with 1 when a finding at or above this severity remains (for CI).',
    )
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('version', negatable: false);

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(
      '${e.message}\n\nUsage: fhc [project] [options]\n${parser.usage}',
    );
    exit(64);
  }
  if (args.flag('help')) {
    stdout.writeln(
      'Audits a Flutter app before a release.\n\nUsage: fhc [project] [options]\n\n${parser.usage}',
    );
    return;
  }
  if (args.flag('version')) {
    stdout.writeln('fhc $toolVersion');
    return;
  }

  final path = args.rest.isEmpty ? '.' : args.rest.first;
  if (!isProject(path)) {
    stderr.writeln('No pubspec.yaml in ${p.absolute(path)}.');
    exit(66);
  }

  stderr.writeln('Checking ${p.normalize(p.absolute(path))} …');
  final report = await audit(
    path,
    network: args.flag('network'),
    analyze: args.flag('analyze'),
    pubGet: args.flag('pub-get'),
    waive: {
      for (final id in args.multiOption('waive'))
        id: 'Accepted on the command line.',
    },
  );

  final out = args.option('out')!;
  final written = <String>[];
  for (final format in args.multiOption('format')) {
    final file = File('$out.$format');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(switch (format) {
      'md' => toMarkdown(report),
      'html' => toHtml(report),
      _ => toJson(report),
    });
    written.add(file.path);
  }

  final overall = report.overall;
  stdout.writeln(
    '\n${report.projectName}: $overall / 100 (${Report.grade(overall)})',
  );
  for (final a in report.areas) {
    stdout.writeln(
      report.skipped.contains(a)
          ? '  ${a.label.padRight(24)}   –  not checked'
          : '  ${a.label.padRight(24)} ${report.scoreFor(a).toString().padLeft(3)}  ${Report.grade(report.scoreFor(a))}',
    );
  }
  final urgent = report.prioritised
      .where((f) => f.severity.index <= Severity.high.index)
      .take(5)
      .toList();
  if (urgent.isNotEmpty) {
    stdout.writeln('\nFix first:');
    for (final f in urgent) {
      stdout.writeln('  [${f.severity.label}] ${f.title.replaceAll('`', '')}');
    }
  }
  stdout.writeln('\nReport: ${written.join(', ')}');

  final failOn = args.option('fail-on')!;
  if (failOn != 'never') {
    final threshold = Severity.values.byName(failOn);
    if (report.findings.any((f) => f.severity.index <= threshold.index)) {
      exit(1);
    }
  }
}
