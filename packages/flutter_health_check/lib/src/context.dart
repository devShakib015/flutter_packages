import 'facts.dart';
import 'model.dart';
import 'project.dart';
import 'pub_client.dart';

/// What every check reads from and writes to besides its findings.
class CheckContext {
  /// A context for one run over [project].
  CheckContext({
    required this.project,
    required this.defaults,
    required this.now,
    this.pub,
    this.analyze = true,
    this.pubGet = false,
    this.dart = 'dart',
    this.flutter = 'flutter',
  });

  /// The project being checked.
  final FlutterProject project;

  /// The Flutter SDK on this machine: what `flutter.targetSdkVersion` means
  /// and which Gradle, AGP and Kotlin versions it refuses.
  final FlutterDefaults defaults;

  /// When the run started; age checks measure from it.
  final DateTime now;

  /// Null when network checks are off.
  final PubClient? pub;

  /// Whether to run `dart analyze` (slow on big apps).
  final bool analyze;

  /// Whether `flutter pub get` may run when packages are not resolved. It
  /// writes .dart_tool and can update pubspec.lock, so it is opt-in.
  final bool pubGet;

  /// The `dart` executable, preferably the one inside the Flutter SDK.
  final String dart;

  /// The `flutter` executable, from the same SDK as [dart].
  final String flutter;

  /// Facts for the report's table, whether or not they are problems.
  final ProjectFacts facts = ProjectFacts();

  /// Checks that could not run, and why.
  final List<String> notes = [];

  /// Rows for the report's dependency table.
  final List<DependencyRow> dependencies = [];

  /// Areas whose checks could not run at all; they get no score.
  final Set<Area> skipped = {};

  /// The Flutter version the project pins (FVM, asdf), when there is one.
  String? pinnedFlutter;

  /// True when the project pins a Flutter other than the one checking it:
  /// what the installed Flutter refuses is then upgrade work, not a broken
  /// build today.
  bool get checksAnUpgrade =>
      pinnedFlutter != null &&
      defaults.flutterVersion != null &&
      !pinnedFlutter!.startsWith(defaults.flutterVersion!);
}
