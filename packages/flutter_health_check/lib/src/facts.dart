import 'dart:io';

import 'package:path/path.dart' as p;

/// Store rules the checks measure against. Each one carries its date and its
/// source, because a report that says "must" has to say who says so. Update
/// these when the stores move; the tests pin them so a change is deliberate.
class StoreRules {
  /// Google Play: new apps and app updates, since 31 Aug 2026.
  static const playTargetSdk = 36;

  /// When [playTargetSdk] took effect.
  static const playTargetSdkSince = '31 August 2026';

  /// The last day for apps that were granted an extension.
  static const playExtensionUntil = '1 November 2026';

  /// Existing apps below this stay listed only for devices up to their target.
  static const playExistingAppFloor = 35;

  /// Google's page for the target API requirement.
  static const playSource =
      'https://developer.android.com/google/play/requirements/target-sdk';

  /// App Store: uploads built with Xcode 26 and the iOS 26 SDK, since 28 Apr 2026.
  static const appStoreSdk = 'Xcode 26 with the iOS 26 SDK';

  /// When [appStoreSdk] became the requirement for uploads.
  static const appStoreSdkSince = '28 April 2026';

  /// Apple's page for upcoming submission requirements.
  static const appStoreSource =
      'https://developer.apple.com/news/upcoming-requirements/';

  /// TN3187: apps built with the SDK after iOS 26 must use the scene life cycle.
  static const sceneSource =
      'https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle';
}

/// What `flutter.targetSdkVersion` and friends resolve to, read from the
/// Flutter SDK on this machine so the report can say what an app that
/// inherits the defaults actually ships with.
class FlutterDefaults {
  /// Values read from a Flutter SDK; see [detect].
  FlutterDefaults({
    this.root,
    this.flutterVersion,
    this.targetSdk,
    this.compileSdk,
    this.minSdk,
    this.iosDeploymentTarget,
    this.floors = const {},
    this.warnings = const {},
  });

  /// The SDK directory, when one was found.
  final String? root;

  /// The SDK's framework version, such as 3.47.5.
  final String? flutterVersion;

  /// What `flutter.targetSdkVersion` resolves to.
  final int? targetSdk;

  /// What `flutter.compileSdkVersion` resolves to.
  final int? compileSdk;

  /// What `flutter.minSdkVersion` resolves to.
  final int? minSdk;

  /// The deployment target in Flutter's iOS app template.
  final String? iosDeploymentTarget;

  /// Below these, Flutter's Gradle plugin fails the build: `gradle`, `agp`,
  /// `kgp`, `minSdk`. Read from its DependencyVersionChecker.
  final Map<String, String> floors;

  /// Below these it builds, with a deprecation warning.
  final Map<String, String> warnings;

  /// Reads the Flutter SDK found through FLUTTER_ROOT or the `flutter` on the
  /// PATH. Fields stay null when there is no SDK, or a file has moved.
  static FlutterDefaults detect() {
    final root = _flutterRoot();
    if (root == null) return FlutterDefaults();
    int? read(String text, String key) => int.tryParse(
      RegExp('$key\\s*:\\s*Int\\s*=\\s*(\\d+)').firstMatch(text)?[1] ?? '',
    );
    final ext = File(
      p.join(
        root,
        'packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt',
      ),
    );
    final extText = ext.existsSync() ? ext.readAsStringSync() : '';
    final pbx = File(
      p.join(
        root,
        'packages/flutter_tools/templates/app/ios.tmpl/Runner.xcodeproj/project.pbxproj.tmpl',
      ),
    );
    final ios = pbx.existsSync()
        ? RegExp(
            r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',
          ).firstMatch(pbx.readAsStringSync())?.group(1)
        : null;
    final checker = File(
      p.join(
        root,
        'packages/flutter_tools/gradle/src/main/kotlin/DependencyVersionChecker.kt',
      ),
    );
    final floors = <String, String>{}, warnings = <String, String>{};
    if (checker.existsSync()) {
      final text = checker.readAsStringSync();
      for (final m in RegExp(
        r'(warn|error)(Gradle|AGP|KGP)Version\s*:\s*\w+\s*=\s*\w+\((\d+),\s*(\d+),\s*(\d+)\)',
      ).allMatches(text)) {
        (m[1] == 'error' ? floors : warnings)[m[2]!.toLowerCase()] =
            '${m[3]}.${m[4]}.${m[5]}';
      }
      for (final m in RegExp(
        r'(warn|error)MinSdkVersion\s*:\s*Int\s*=\s*(\d+)',
      ).allMatches(text)) {
        (m[1] == 'error' ? floors : warnings)['minSdk'] = m[2]!;
      }
    }
    final versionFile = File(p.join(root, 'bin/cache/flutter.version.json'));
    String? version;
    if (versionFile.existsSync()) {
      version = RegExp(
        r'"frameworkVersion"\s*:\s*"([^"]+)"',
      ).firstMatch(versionFile.readAsStringSync())?[1];
    }
    return FlutterDefaults(
      root: root,
      flutterVersion: version,
      targetSdk: read(extText, 'targetSdkVersion'),
      compileSdk: read(extText, 'compileSdkVersion'),
      minSdk: read(extText, 'minSdkVersion'),
      iosDeploymentTarget: ios,
      floors: floors,
      warnings: warnings,
    );
  }

  static String? _flutterRoot() {
    final env = Platform.environment['FLUTTER_ROOT'];
    if (env != null && Directory(env).existsSync()) return env;
    try {
      final which = Process.runSync(Platform.isWindows ? 'where' : 'which', [
        'flutter',
      ]);
      // `where` lists every match, flutter and flutter.bat among them.
      final bin = (which.stdout as String)
          .trim()
          .split(RegExp(r'[\r\n]+'))
          .first
          .trim();
      if (bin.isEmpty) return null;
      final resolved = File(bin).resolveSymbolicLinksSync();
      return p.dirname(p.dirname(resolved));
    } catch (_) {
      return null;
    }
  }
}

/// Compares dotted versions numerically: 8.14 > 8.9, 1.8.22 < 1.9.
int compareVersions(String a, String b) {
  List<int> parts(String v) => RegExp(r'\d+')
      .allMatches(v.split(RegExp(r'[-+]')).first)
      .map((m) => int.parse(m[0]!))
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
