// Audits a Flutter project from Dart code and fails when anything high or
// critical is open: what `fhc --fail-on high` does, for a build script that
// wants the report as data.
//
//   dart run example/flutter_health_check_example.dart path/to/app
import 'dart:io';

import 'package:flutter_health_check/flutter_health_check.dart';

Future<void> main(List<String> args) async {
  final path = args.isEmpty ? '.' : args.first;
  if (!isProject(path)) {
    stderr.writeln('usage: flutter_health_check_example <flutter-project>');
    exitCode = 64;
    return;
  }

  // analyze: false skips `dart analyze`, the slow part on a large app.
  final report = await audit(path, analyze: false);
  File('health-report.md').writeAsStringSync(toMarkdown(report));

  final overall = report.overall;
  stdout.writeln(
    '${report.projectName}: $overall / 100 (${Report.grade(overall)})',
  );
  final blocking = report.prioritised
      .where((f) => f.severity.index <= Severity.high.index)
      .toList();
  for (final f in blocking) {
    stdout.writeln('  [${f.severity.label}] ${f.id}: ${f.title}');
  }
  if (blocking.isNotEmpty) exitCode = 1;
}
