import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../facts.dart';
import '../model.dart';
import '../project.dart';
import '../text.dart';

/// Google Play and the Android build: targetSdk, minSdk, the Gradle toolchain
/// Flutter accepts, the application ID, release signing and the manifest.
List<Finding> checkAndroid(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  if (!project.exists('android')) {
    ctx.notes.add(
      'No android/ folder, so the Android and Google Play checks did not run.',
    );
    ctx.skipped.add(Area.android);
    return findings;
  }

  final gradle = project.firstFile([
    'android/app/build.gradle.kts',
    'android/app/build.gradle',
  ]);
  if (gradle == null) {
    ctx.notes.add(
      'No android/app/build.gradle(.kts), so targetSdk, minSdk, the application ID '
      'and release signing were not checked.',
    );
  } else {
    findings.addAll(_appGradle(ctx, gradle));
  }
  findings.addAll(_toolchain(ctx));
  findings.addAll(_manifests(ctx));
  return findings;
}

List<Finding> _appGradle(CheckContext ctx, File file) {
  final project = ctx.project, d = ctx.defaults;
  final rel = project.rel(file.path);
  final code = stripComments(file.readAsStringSync());
  final findings = <Finding>[];
  final flutter = d.flutterVersion == null
      ? 'the installed Flutter'
      : 'Flutter ${d.flutterVersion}';

  // targetSdk: the one Google Play enforces.
  final targets = _sdkValues(code, 'targetSdk', d.targetSdk);
  if (targets.isEmpty) {
    ctx.notes.add(
      'No targetSdk in $rel. Without one, the build targets compileSdk; confirm '
      'what it resolves to.',
    );
  }
  for (final t in targets) {
    ctx.facts['targetSdk'] = t.describe(flutter);
    if (t.value == null) {
      ctx.notes.add(
        'targetSdk in $rel is `${t.token}`, which this check could not resolve. '
        'Confirm it is at least ${StoreRules.playTargetSdk}.',
      );
    }
  }
  final lowTarget = targets.where(
    (t) => t.value != null && t.value! < StoreRules.playTargetSdk,
  );
  if (lowTarget.isNotEmpty) {
    final lowest = lowTarget.reduce((a, b) => a.value! <= b.value! ? a : b);
    findings.add(
      Finding(
        id: 'android.target-sdk',
        area: Area.android,
        severity: Severity.critical,
        title:
            'targetSdk is ${lowest.value}; Google Play requires ${StoreRules.playTargetSdk} '
            'for new apps and updates',
        detail:
            'Since ${StoreRules.playTargetSdkSince}, Google Play accepts new apps and app '
            'updates only if they target API level ${StoreRules.playTargetSdk} (Android 16). Apps '
            'that were granted an extension have until ${StoreRules.playExtensionUntil}.'
            '${lowest.value! < StoreRules.playExistingAppFloor ? ' Below API ${StoreRules.playExistingAppFloor}, the app already published is also hidden from new users on devices running a newer Android version.' : ''}',
        fix:
            'Set targetSdk to ${StoreRules.playTargetSdk}, then test the Android 16 changes that '
            'come with it: edge-to-edge can no longer be switched off, predictive back is on by '
            'default, and on tablets and foldables the app\'s orientation and aspect-ratio locks '
            'are ignored. Source: ${StoreRules.playSource}',
        locations: [
          for (final t in lowTarget) '$rel:${lineOf(code, t.offset)}',
        ],
      ),
    );
  }

  final compile = _sdkValues(code, 'compileSdk', d.compileSdk);
  if (compile.isNotEmpty) {
    ctx.facts['compileSdk'] = compile.first.describe(flutter);
  }

  // minSdk: Flutter's Gradle plugin refuses to build below its floor.
  final mins = _sdkValues(code, 'minSdk', d.minSdk);
  if (mins.isNotEmpty) ctx.facts['minSdk'] = mins.first.describe(flutter);
  final floor = int.tryParse(d.floors['minSdk'] ?? ''),
      warn = int.tryParse(d.warnings['minSdk'] ?? '');
  for (final m in mins.where((m) => m.value != null)) {
    if (floor != null && m.value! < floor) {
      findings.add(
        Finding(
          id: 'android.min-sdk-unsupported',
          area: Area.android,
          severity: ctx.checksAnUpgrade ? Severity.medium : Severity.high,
          title: 'minSdk ${m.value} is below what $flutter will build ($floor)',
          detail:
              'Flutter\'s Gradle plugin stops the build when minSdk is under $floor, so the app '
              'cannot move to current Flutter until this is raised.'
              '${ctx.checksAnUpgrade ? ' (The Flutter ${ctx.pinnedFlutter} it pins still builds it.)' : ''}',
          fix:
              'Raise minSdk to at least $floor (Flutter\'s default is ${d.minSdk ?? warn ?? floor}).',
          locations: ['$rel:${lineOf(code, m.offset)}'],
        ),
      );
    } else if (warn != null && m.value! < warn) {
      findings.add(
        Finding(
          id: 'android.min-sdk-deprecated',
          area: Area.android,
          severity: Severity.low,
          title: 'minSdk ${m.value} is on its way out of Flutter\'s support',
          detail:
              '$flutter still builds it but warns that support below API $warn will be '
              'removed in a later release.',
          fix: 'Plan to raise minSdk to $warn.',
          locations: ['$rel:${lineOf(code, m.offset)}'],
        ),
      );
    }
  }

  // The application ID.
  final appId = RegExp(
    r'''\bapplicationId\s*(?:=\s*)?["']([^"']+)["']''',
  ).firstMatch(code);
  String? id = appId?[1];
  var idLocation = appId == null ? null : '$rel:${lineOf(code, appId.start)}';
  if (id == null) {
    final manifest = project.file('android/app/src/main/AndroidManifest.xml');
    if (manifest.existsSync()) {
      final text = manifest.readAsStringSync();
      final m = RegExp(
        r'''\bpackage\s*=\s*["']([^"']+)["']''',
      ).firstMatch(text);
      id = m?[1];
      if (m != null) {
        idLocation = '${project.rel(manifest.path)}:${lineOf(text, m.start)}';
      }
    }
  }
  if (id != null) {
    ctx.facts['Android application ID'] = id;
    if (id == 'com.example' || id.startsWith('com.example.')) {
      findings.add(
        Finding(
          id: 'android.example-id',
          area: Area.android,
          severity: Severity.high,
          title: 'The application ID is still the template\'s `$id`',
          detail:
              'Google Play rejects package names that start with com.example, and the ID can '
              'never change once the app is published.',
          fix:
              'Pick a reverse-domain ID you own (for example com.yourcompany.app) and set it as '
              'applicationId; update the namespace and the Kotlin package to match.',
          locations: [?idLocation],
        ),
      );
    }
  }

  // Release builds signed with the debug key.
  final types = block(code, RegExp(r'\bbuildTypes\s*'));
  if (types != null) {
    final release = block(
      code,
      RegExp(r'''(?:\brelease|getByName\s*\(\s*["']release["']\s*\))\s*'''),
      types.$1,
      types.$2,
    );
    if (release != null) {
      final body = code.substring(release.$1, release.$2);
      final debug = RegExp(
        r'''signingConfig\s*=?\s*signingConfigs\s*\.\s*(?:debug\b|getByName\s*\(\s*["']debug["']\s*\))''',
      ).firstMatch(body);
      if (debug != null) {
        findings.add(
          Finding(
            id: 'android.debug-signing',
            area: Area.android,
            severity: Severity.high,
            title: 'Release builds are signed with the debug key',
            detail:
                'This is the template\'s placeholder so that `flutter run --release` works. '
                'Google Play rejects uploads signed with a debug key. (If a CI step signs the '
                'bundle after the build, this does not apply.)',
            fix:
                'Create an upload keystore, load its passwords from a key.properties file kept '
                'out of git, and give release its own signingConfig: '
                'https://docs.flutter.dev/deployment/android#sign-the-app',
            locations: ['$rel:${lineOf(code, release.$1 + debug.start)}'],
          ),
        );
      }
    }
  }
  return findings;
}

class _Sdk {
  _Sdk(this.token, this.value, this.offset);

  final String token;
  final int? value;
  final int offset;

  String describe(String flutter) => value == null
      ? token
      : int.tryParse(token) != null
      ? '$value'
      : '$value ($token, $flutter)';
}

/// Every `targetSdk = 34`, `targetSdkVersion 34`, `targetSdk = flutter.targetSdkVersion`
/// in [code]; `flutter.*` resolves to [flutterDefault].
List<_Sdk> _sdkValues(String code, String key, int? flutterDefault) => [
  for (final m in RegExp(
    '(?<![\\w.])$key(?:Version)?\\b\\s*(?:=\\s*|\\(\\s*|[ \\t]+)([A-Za-z0-9_.]+)',
  ).allMatches(code))
    _Sdk(
      m[1]!,
      int.tryParse(m[1]!) ??
          (m[1]!.startsWith('flutter.') ? flutterDefault : null),
      m.start,
    ),
];

List<Finding> _toolchain(CheckContext ctx) {
  final project = ctx.project, d = ctx.defaults;
  final findings = <Finding>[];
  final flutter = d.flutterVersion == null
      ? 'the installed Flutter'
      : 'Flutter ${d.flutterVersion}';

  String? read(String rel) {
    final f = project.file(rel);
    return f.existsSync() ? stripComments(f.readAsStringSync()) : null;
  }

  // A .properties file: `#` comments, and `https\://` must survive.
  final wrapperFile = project.file(
    'android/gradle/wrapper/gradle-wrapper.properties',
  );
  final wrapper = wrapperFile.existsSync()
      ? wrapperFile.readAsStringSync()
      : null;
  final settings =
      read('android/settings.gradle.kts') ??
      read('android/settings.gradle') ??
      '';
  final build =
      read('android/build.gradle.kts') ?? read('android/build.gradle') ?? '';
  final catalog = read('android/gradle/libs.versions.toml') ?? '';

  String? first(List<(String, RegExp)> sources) {
    for (final (text, re) in sources) {
      final m = re.firstMatch(text);
      if (m != null) return m[1];
    }
    return null;
  }

  final versions = {
    'gradle': (
      'Gradle',
      wrapper == null
          ? null
          : RegExp(
              r'gradle-(\d+(?:\.\d+)*)(?:-rc-?\d+)?-(?:all|bin)\.zip',
            ).firstMatch(wrapper)?[1],
      'android/gradle/wrapper/gradle-wrapper.properties (distributionUrl)',
    ),
    'agp': (
      'Android Gradle Plugin',
      first([
        (
          settings,
          RegExp(
            r'''id\s*\(?\s*["']com\.android\.application["']\s*\)?\s*version\s*\(?\s*["']([^"']+)["']''',
          ),
        ),
        (build, RegExp(r'''com\.android\.tools\.build:gradle:(\d[\w.-]*)''')),
        (
          catalog,
          RegExp(
            r'''^\s*(?:agp|androidGradlePlugin|android-gradle-plugin|androidGradle)\s*=\s*["']([^"']+)["']''',
            multiLine: true,
          ),
        ),
      ]),
      'android/settings.gradle(.kts), in the plugins block',
    ),
    'kgp': (
      'Kotlin Gradle Plugin',
      first([
        (
          settings,
          RegExp(
            r'''id\s*\(?\s*["']org\.jetbrains\.kotlin\.android["']\s*\)?\s*version\s*\(?\s*["']([^"']+)["']''',
          ),
        ),
        (build, RegExp(r'''\bkotlin_version\s*=\s*["']([^"']+)["']''')),
        (build, RegExp(r'''kotlin-gradle-plugin:(\d[\w.-]*)''')),
        (
          catalog,
          RegExp(r'''^\s*kotlin\s*=\s*["']([^"']+)["']''', multiLine: true),
        ),
      ]),
      'android/settings.gradle(.kts), in the plugins block',
    ),
  };

  for (final MapEntry(key: key, value: (name, version, where))
      in versions.entries) {
    if (version == null) {
      if (key != 'kgp') {
        ctx.notes.add(
          'Could not find the $name version, so it was not compared with what '
          '$flutter supports.',
        );
      }
      continue;
    }
    ctx.facts[name] = version;
    final floor = d.floors[key], warn = d.warnings[key];
    if (floor != null && compareVersions(version, floor) < 0) {
      findings.add(
        Finding(
          id: 'android.$key-unsupported',
          area: Area.android,
          severity: ctx.checksAnUpgrade ? Severity.medium : Severity.high,
          title: '$name $version is below what $flutter will build ($floor)',
          detail:
              'Flutter\'s Gradle plugin stops the build when $name is older than $floor. '
              'The app cannot move to current Flutter (and its targetSdk and plugin updates) '
              'until this is upgraded.'
              '${ctx.checksAnUpgrade ? ' The Flutter ${ctx.pinnedFlutter} it pins still builds it, so this is upgrade work, not a broken build.' : ''}',
          fix:
              'Upgrade $name to $warn or later in $where. Upgrade Gradle, AGP and Kotlin '
              'together: each AGP version needs a minimum Gradle.',
          locations: [where.split(' ').first],
        ),
      );
    } else if (warn != null && compareVersions(version, warn) < 0) {
      findings.add(
        Finding(
          id: 'android.$key-deprecated',
          area: Area.android,
          severity: Severity.low,
          title: '$name $version will soon be too old for Flutter',
          detail:
              '$flutter still builds with it but warns that support below $warn is being '
              'removed.',
          fix: 'Upgrade $name to $warn or later in $where.',
          locations: [where.split(' ').first],
        ),
      );
    }
  }
  if (d.floors.isEmpty) {
    ctx.notes.add(
      'Could not read Flutter\'s supported Gradle, AGP and Kotlin versions from the '
      'SDK, so those were not compared.',
    );
  }
  return findings;
}

/// Play policies that gate a permission: severity, and what the policy says.
const _restricted = <String, (Severity, String)>{
  'MANAGE_EXTERNAL_STORAGE': (
    Severity.high,
    'All-files access is approved only for apps whose core purpose needs it, such as file '
        'managers, backup and antivirus apps. Others are rejected. Use scoped storage or the '
        'system file pickers.',
  ),
  'QUERY_ALL_PACKAGES': (
    Severity.high,
    'Seeing every installed app needs a Play Console declaration and is approved for few app '
        'types. List the packages you actually query in a <queries> element instead.',
  ),
  'READ_SMS': (Severity.high, _sms),
  'SEND_SMS': (Severity.high, _sms),
  'RECEIVE_SMS': (Severity.high, _sms),
  'RECEIVE_MMS': (Severity.high, _sms),
  'RECEIVE_WAP_PUSH': (Severity.high, _sms),
  'READ_CALL_LOG': (Severity.high, _sms),
  'WRITE_CALL_LOG': (Severity.high, _sms),
  'PROCESS_OUTGOING_CALLS': (Severity.high, _sms),
  'ACCESS_BACKGROUND_LOCATION': (
    Severity.medium,
    'Background location needs a Play Console declaration, a video of the feature that uses '
        'it, and review. Apps without a clear, user-facing reason are rejected.',
  ),
  'REQUEST_INSTALL_PACKAGES': (
    Severity.medium,
    'Installing packages needs a Play Console declaration and is allowed only for a few uses. '
        'An app from Google Play may not update itself outside Google Play.',
  ),
  'USE_EXACT_ALARM': (
    Severity.medium,
    'USE_EXACT_ALARM is only for alarm clock, timer and calendar apps. Others should request '
        'SCHEDULE_EXACT_ALARM or use inexact alarms.',
  ),
  'USE_FULL_SCREEN_INTENT': (
    Severity.medium,
    'Full-screen intents are meant for calling and alarm apps. For other apps the permission '
        'is not granted by default, and Play Console asks for a declaration.',
  ),
  'READ_MEDIA_IMAGES': (Severity.medium, _media),
  'READ_MEDIA_VIDEO': (Severity.medium, _media),
};

const _sms =
    'SMS and call-log permissions are restricted to the default SMS, phone or '
    'assistant app, plus a short list of exceptions. For one-time codes, the SMS Retriever and '
    'SMS User Consent APIs need no permission.';
const _media =
    'Broad photo and video access needs a Play Console declaration. Apps that '
    'only need a picture now and then must use the system photo picker, which needs no '
    'permission.';

List<Finding> _manifests(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  final src = project.dir('android/app/src');
  if (!src.existsSync()) return findings;
  final manifests =
      [
          for (final d in src.listSync().whereType<Directory>())
            if (!const {
              'debug',
              'profile',
              'test',
              'androidTest',
            }.contains(p.basename(d.path)))
              File(p.join(d.path, 'AndroidManifest.xml')),
        ].where((f) => f.existsSync()).toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final permissions = <String, List<String>>{};
  for (final f in manifests) {
    final rel = project.rel(f.path);
    final xml = stripXmlComments(f.readAsStringSync());

    final debuggable = RegExp(
      r'''android:debuggable\s*=\s*["']true["']''',
    ).firstMatch(xml);
    if (debuggable != null) {
      findings.add(
        Finding(
          id: 'android.debuggable',
          area: Area.android,
          severity: Severity.critical,
          title: 'The manifest marks the app as debuggable',
          detail:
              'A debuggable build lets anyone attach a debugger and read its memory. '
              'Google Play rejects debuggable uploads.',
          fix:
              'Remove android:debuggable; the build type sets it for debug builds.',
          locations: ['$rel:${lineOf(xml, debuggable.start)}'],
        ),
      );
    }

    final cleartext = RegExp(
      r'''android:usesCleartextTraffic\s*=\s*["']true["']''',
    ).firstMatch(xml);
    if (cleartext != null) {
      findings.add(_cleartext('$rel:${lineOf(xml, cleartext.start)}'));
    }

    final config = RegExp(
      r'''android:networkSecurityConfig\s*=\s*["']@xml/([\w]+)["']''',
    ).firstMatch(xml);
    if (config != null) {
      final cfg = project.file(
        'android/app/src/${p.basename(f.parent.path)}/res/xml/${config[1]}.xml',
      );
      if (cfg.existsSync()) findings.addAll(_networkConfig(project, cfg));
    }

    for (final m in RegExp(
      r'<uses-permission(?:-sdk-23)?\b([^>]*)>',
    ).allMatches(xml)) {
      final attrs = m[1]!;
      if (RegExp(r'''tools:node\s*=\s*["']remove["']''').hasMatch(attrs)) {
        continue;
      }
      final name = RegExp(
        r'''android:name\s*=\s*["']([^"']+)["']''',
      ).firstMatch(attrs)?[1];
      if (name == null) continue;
      permissions
          .putIfAbsent(name, () => [])
          .add('$rel:${lineOf(xml, m.start)}');
    }
  }
  if (manifests.isNotEmpty) {
    ctx.facts['Android permissions (app manifest)'] = permissions.isEmpty
        ? 'none'
        : permissions.keys.map((k) => k.split('.').last).join(', ');
  }

  for (final e in permissions.entries) {
    final short = e.key.split('.').last;
    final rule = e.key.startsWith('android.permission.')
        ? _restricted[short]
        : null;
    if (rule == null) continue;
    findings.add(
      Finding(
        id: 'android.restricted-permission',
        area: Area.android,
        severity: rule.$1,
        title: 'Uses $short, which Google Play restricts',
        detail: rule.$2,
        fix:
            'Remove it if the app can work without it; otherwise prepare the Play Console '
            'declaration before release.',
        locations: e.value,
      ),
    );
  }

  final health = [
    for (final k in permissions.keys)
      if (k.startsWith('android.permission.health.')) k.substring(26),
  ];
  if (health.isNotEmpty) {
    findings.add(
      Finding(
        id: 'android.health-connect',
        area: Area.android,
        severity: Severity.medium,
        title: 'Health Connect data to declare: ${health.join(', ')}',
        detail:
            'Google Play reviews access to Health Connect: the Health apps declaration in '
            'Play Console must list each data type and why the app needs it, and access is '
            'granted only for the uses the policy allows.',
        fix:
            'Request only the data types the features use, and prepare the declaration (App '
            'content → Health apps) before submitting.',
        locations: [
          for (final k in permissions.keys)
            if (k.startsWith('android.permission.health.')) ...permissions[k]!,
        ],
      ),
    );
  }
  final exactAlarm = permissions['android.permission.SCHEDULE_EXACT_ALARM'];
  if (exactAlarm != null &&
      !permissions.containsKey('android.permission.USE_EXACT_ALARM')) {
    findings.add(
      Finding(
        id: 'android.exact-alarm-denied',
        area: Area.android,
        severity: Severity.low,
        title: 'Exact alarms are off by default for new installs',
        detail:
            'Since Android 14, SCHEDULE_EXACT_ALARM is denied by default for newly installed '
            'apps (apart from alarm and calendar apps), so scheduling an exact alarm fails until '
            'the user turns it on in settings.',
        fix:
            'Check canScheduleExactAlarms() before scheduling; fall back to an inexact alarm or '
            'send the user to the setting.',
        locations: exactAlarm,
      ),
    );
  }

  final services = [
    for (final k in permissions.keys)
      if (k.startsWith('android.permission.FOREGROUND_SERVICE_'))
        k.substring(38),
  ];
  if (services.isNotEmpty) {
    findings.add(
      Finding(
        id: 'android.foreground-service-types',
        area: Area.android,
        severity: Severity.low,
        title: 'Foreground service types to declare: ${services.join(', ')}',
        detail:
            'For apps targeting Android 14 or later, Play Console asks for a declaration of '
            'each foreground service type, with a description and a video of the feature.',
        fix:
            'Prepare the declaration (App content → Foreground service permissions) before '
            'submitting.',
        locations: [
          for (final k in permissions.keys)
            if (k.contains('FOREGROUND_SERVICE_')) ...permissions[k]!,
        ],
      ),
    );
  }
  return findings;
}

Finding _cleartext(String location) => Finding(
  id: 'security.android-cleartext',
  area: Area.security,
  severity: Severity.high,
  title: 'Android allows unencrypted HTTP for every domain',
  detail:
      'Anyone on the same network (public Wi-Fi, a compromised router) can read and '
      'change unencrypted traffic, including tokens and personal data.',
  fix:
      'Remove the cleartext permission and use HTTPS. If one host really needs HTTP (a '
      'local device, a dev server), allow only that domain in a network security config.',
  locations: [location],
);

List<Finding> _networkConfig(FlutterProject project, File file) {
  final rel = project.rel(file.path);
  final xml = stripXmlComments(file.readAsStringSync());
  final findings = <Finding>[];
  final base = RegExp(
    r'''<base-config\b[^>]*cleartextTrafficPermitted\s*=\s*["']true["']''',
  ).firstMatch(xml);
  if (base != null) findings.add(_cleartext('$rel:${lineOf(xml, base.start)}'));
  final domains = <String>[];
  for (final m in RegExp(
    r'''<domain-config\b[^>]*cleartextTrafficPermitted\s*=\s*["']true["'][^>]*>([\s\S]*?)</domain-config>''',
  ).allMatches(xml)) {
    domains.addAll(
      RegExp(
        r'<domain[^>]*>\s*([^<\s]+)\s*</domain>',
      ).allMatches(m[1]!).map((d) => d[1]!),
    );
  }
  final remote = domains
      .where(
        (d) => !RegExp(
          r'^(localhost|127\.0\.0\.1|10\.0\.2\.2|10\.0\.3\.2)$',
        ).hasMatch(d),
      )
      .toList();
  if (remote.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.android-cleartext-domains',
        area: Area.security,
        severity: Severity.low,
        title: 'Unencrypted HTTP allowed for ${remote.join(', ')}',
        detail:
            'Traffic to these hosts can be read and changed on the network.',
        fix: 'Move them to HTTPS, or confirm they carry nothing sensitive.',
        locations: [rel],
      ),
    );
  }
  return findings;
}
