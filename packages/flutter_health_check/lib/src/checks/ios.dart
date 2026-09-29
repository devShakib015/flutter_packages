import 'dart:io';

import 'package:yaml/yaml.dart';

import '../context.dart';
import '../facts.dart';
import '../model.dart';
import '../project.dart';
import '../text.dart';

/// Purpose strings a plugin needs, as (any one of these keys, only when the
/// Dart code matches this pattern). A plugin's README can ask for more than
/// the app uses: image_picker's gallery needs no permission (PHPicker), and
/// apps that never open the camera ship without a camera string.
const pluginUsageKeys = <String, List<(List<String>, String?)>>{
  'image_picker': [
    (['NSCameraUsageDescription'], r'ImageSource\.camera'),
    (
      ['NSMicrophoneUsageDescription'],
      r'pickVideo\s*\(\s*source:\s*ImageSource\.camera',
    ),
  ],
  'camera': [
    (['NSCameraUsageDescription'], null),
    (['NSMicrophoneUsageDescription'], null),
  ],
  'mobile_scanner': [
    (['NSCameraUsageDescription'], null),
  ],
  'qr_code_scanner': [
    (['NSCameraUsageDescription'], null),
  ],
  'qr_code_scanner_plus': [
    (['NSCameraUsageDescription'], null),
  ],
  'flutter_barcode_scanner': [
    (['NSCameraUsageDescription'], null),
  ],
  'geolocator': [
    (
      [
        'NSLocationWhenInUseUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
      ],
      r'getCurrentPosition|getPositionStream|requestPermission',
    ),
  ],
  'location': [
    (
      [
        'NSLocationWhenInUseUsageDescription',
        'NSLocationAlwaysAndWhenInUseUsageDescription',
      ],
      null,
    ),
  ],
  'local_auth': [
    (['NSFaceIDUsageDescription'], null),
  ],
  'flutter_contacts': [
    (['NSContactsUsageDescription'], null),
  ],
  'contacts_service': [
    (['NSContactsUsageDescription'], null),
  ],
  'record': [
    (['NSMicrophoneUsageDescription'], null),
  ],
  'flutter_sound': [
    (['NSMicrophoneUsageDescription'], null),
  ],
  'speech_to_text': [
    (['NSSpeechRecognitionUsageDescription'], null),
    (['NSMicrophoneUsageDescription'], null),
  ],
  'flutter_blue_plus': [
    (['NSBluetoothAlwaysUsageDescription'], null),
  ],
  'health': [
    (['NSHealthShareUsageDescription'], null),
  ],
  'app_tracking_transparency': [
    (['NSUserTrackingUsageDescription'], null),
  ],
  'photo_manager': [
    (['NSPhotoLibraryUsageDescription'], null),
  ],
  'gal': [
    (
      ['NSPhotoLibraryAddUsageDescription', 'NSPhotoLibraryUsageDescription'],
      null,
    ),
  ],
  'image_gallery_saver': [
    (
      ['NSPhotoLibraryAddUsageDescription', 'NSPhotoLibraryUsageDescription'],
      null,
    ),
  ],
  'image_gallery_saver_plus': [
    (
      ['NSPhotoLibraryAddUsageDescription', 'NSPhotoLibraryUsageDescription'],
      null,
    ),
  ],
  'saver_gallery': [
    (
      ['NSPhotoLibraryAddUsageDescription', 'NSPhotoLibraryUsageDescription'],
      null,
    ),
  ],
  'device_calendar': [
    (
      ['NSCalendarsFullAccessUsageDescription', 'NSCalendarsUsageDescription'],
      null,
    ),
  ],
  'nfc_manager': [
    (['NFCReaderUsageDescription'], null),
  ],
  'flutter_webrtc': [
    (['NSCameraUsageDescription'], null),
    (['NSMicrophoneUsageDescription'], null),
  ],
  'agora_rtc_engine': [
    (['NSCameraUsageDescription'], null),
    (['NSMicrophoneUsageDescription'], null),
  ],
  'pedometer': [
    (['NSMotionUsageDescription'], null),
  ],
};

/// permission_handler's `Permission.x` → the purpose string iOS needs.
const permissionUsageKeys = <String, List<String>>{
  'camera': ['NSCameraUsageDescription'],
  'microphone': ['NSMicrophoneUsageDescription'],
  'photos': ['NSPhotoLibraryUsageDescription'],
  'photosAddOnly': ['NSPhotoLibraryAddUsageDescription'],
  'location': ['NSLocationWhenInUseUsageDescription'],
  'locationWhenInUse': ['NSLocationWhenInUseUsageDescription'],
  'locationAlways': ['NSLocationAlwaysAndWhenInUseUsageDescription'],
  'contacts': ['NSContactsUsageDescription'],
  'calendar': [
    'NSCalendarsFullAccessUsageDescription',
    'NSCalendarsUsageDescription',
  ],
  'calendarFullAccess': ['NSCalendarsFullAccessUsageDescription'],
  'calendarWriteOnly': ['NSCalendarsWriteOnlyAccessUsageDescription'],
  'reminders': [
    'NSRemindersFullAccessUsageDescription',
    'NSRemindersUsageDescription',
  ],
  'speech': ['NSSpeechRecognitionUsageDescription'],
  'bluetooth': ['NSBluetoothAlwaysUsageDescription'],
  'appTrackingTransparency': ['NSUserTrackingUsageDescription'],
  'sensors': ['NSMotionUsageDescription'],
  'mediaLibrary': ['NSAppleMusicUsageDescription'],
};

/// permission_handler's `Permission.x` → the Podfile macro that compiles it
/// in when the plugin is integrated with CocoaPods (all default to 0).
const permissionMacros = <String, List<String>>{
  'camera': ['PERMISSION_CAMERA'],
  'microphone': ['PERMISSION_MICROPHONE'],
  'photos': ['PERMISSION_PHOTOS'],
  'photosAddOnly': ['PERMISSION_PHOTOS_ADD_ONLY'],
  'location': ['PERMISSION_LOCATION'],
  'locationAlways': ['PERMISSION_LOCATION'],
  'locationWhenInUse': ['PERMISSION_LOCATION', 'PERMISSION_LOCATION_WHENINUSE'],
  'contacts': ['PERMISSION_CONTACTS'],
  'calendar': ['PERMISSION_EVENTS'],
  'calendarWriteOnly': ['PERMISSION_EVENTS'],
  'calendarFullAccess': ['PERMISSION_EVENTS_FULL_ACCESS'],
  'reminders': ['PERMISSION_REMINDERS'],
  'speech': ['PERMISSION_SPEECH_RECOGNIZER'],
  'notification': ['PERMISSION_NOTIFICATIONS'],
  'mediaLibrary': ['PERMISSION_MEDIA_LIBRARY'],
  'sensors': ['PERMISSION_SENSORS'],
  'bluetooth': ['PERMISSION_BLUETOOTH'],
  'appTrackingTransparency': ['PERMISSION_APP_TRACKING_TRANSPARENCY'],
  'criticalAlerts': ['PERMISSION_CRITICAL_ALERTS'],
  'assistant': ['PERMISSION_ASSISTANT'],
};

/// The App Store and the iOS build: purpose strings, permission_handler's
/// Podfile switches, the UIScene life cycle, App Transport Security and the
/// bundle ID.
List<Finding> checkIos(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  if (!project.exists('ios')) {
    ctx.notes.add(
      'No ios/ folder, so the iOS and App Store checks did not run.',
    );
    ctx.skipped.add(Area.ios);
    return findings;
  }
  final plistFile = project.file('ios/Runner/Info.plist');
  if (!plistFile.existsSync()) {
    ctx.notes.add(
      'No ios/Runner/Info.plist, so purpose strings, App Transport Security and '
      'the scene life cycle were not checked.',
    );
    ctx.skipped.add(Area.ios);
    return findings;
  }
  final plistText = plistFile.readAsStringSync();
  final plist = parsePlist(plistText);
  if (plist is! Map<String, Object?>) {
    ctx.notes.add(
      'ios/Runner/Info.plist could not be read as a property list.',
    );
    ctx.skipped.add(Area.ios);
    return findings;
  }
  final pbx = project.file('ios/Runner.xcodeproj/project.pbxproj');
  final pbxText = pbx.existsSync() ? pbx.readAsStringSync() : '';

  findings.addAll(_purposeStrings(ctx, plist, plistText, pbxText));
  findings.addAll(_permissionHandlerMacros(ctx.project));
  findings.addAll(_transportSecurity(plist, plistText));

  if (!plist.containsKey('UIApplicationSceneManifest')) {
    findings.add(
      Finding(
        id: 'ios.no-scene-life-cycle',
        area: Area.ios,
        severity: Severity.high,
        title: 'The app does not use the UIScene life cycle',
        detail:
            'Apple\'s TN3187: apps built with the SDK released after iOS 26 must adopt the '
            'scene-based life cycle, or they will not launch. The app is fine on Xcode 26; the '
            'first build with Xcode 27 is the one that breaks.',
        fix:
            'Migrate before moving to Xcode 27: add the UIApplicationSceneManifest entry and a '
            'SceneDelegate as the current Flutter app template does (Flutter documents the '
            'migration), then check that deep links, push notifications and URL callbacks from '
            'plugins still arrive. Source: ${StoreRules.sceneSource}',
        locations: ['ios/Runner/Info.plist'],
      ),
    );
  }

  // Bundle identifiers of the app target (not the test target).
  final ids = {
    for (final m in RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;',
    ).allMatches(pbxText))
      if (!m[1]!.endsWith('Tests')) m[1]!,
  };
  if (ids.isNotEmpty) ctx.facts['iOS bundle ID'] = ids.join(', ');
  final example = ids.where(
    (id) => id == 'com.example' || id.startsWith('com.example.'),
  );
  if (example.isNotEmpty) {
    final m = RegExp(
      'PRODUCT_BUNDLE_IDENTIFIER = "?${RegExp.escape(example.first)}"?;',
    ).firstMatch(pbxText)!;
    findings.add(
      Finding(
        id: 'ios.example-id',
        area: Area.ios,
        severity: Severity.medium,
        title: 'The bundle ID is still the template\'s `${example.first}`',
        detail:
            'The bundle ID cannot change once the app is on the App Store, and com.example '
            'is a placeholder domain nobody owns.',
        fix:
            'Set PRODUCT_BUNDLE_IDENTIFIER to a reverse-domain ID you own, in all three build '
            'configurations.',
        locations: [
          'ios/Runner.xcodeproj/project.pbxproj:${lineOf(pbxText, m.start)}',
        ],
      ),
    );
  }

  final targets =
      RegExp(
          r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);',
        ).allMatches(pbxText).map((m) => m[1]!).toSet().toList()
        ..sort(compareVersions);
  if (targets.isNotEmpty) {
    ctx.facts['iOS deployment target'] = targets.length == 1
        ? targets.single
        : '${targets.join(', ')} (differs between build configurations)';
  }
  final podfile = project.file('ios/Podfile');
  if (podfile.existsSync()) {
    final m = RegExp(
      r'''^\s*platform\s+:ios\s*,\s*['"]([\d.]+)['"]''',
      multiLine: true,
    ).firstMatch(podfile.readAsStringSync());
    ctx.facts['Podfile platform'] =
        m?[1] ?? 'not set (CocoaPods picks a default per pod)';
  }
  ctx.facts['iOS privacy manifest (app)'] =
      project.file('ios/Runner/PrivacyInfo.xcprivacy').existsSync()
      ? 'present'
      : 'none';
  return findings;
}

List<Finding> _purposeStrings(
  CheckContext ctx,
  Map<String, Object?> plist,
  String plistText,
  String pbxText,
) {
  final project = ctx.project;
  final findings = <Finding>[];

  // Keys can also come from build settings (INFOPLIST_KEY_…) or be localised
  // in InfoPlist.strings; either counts as present.
  final present = <String, String>{
    for (final e in plist.entries)
      if (e.value is String) e.key: e.value as String,
  };
  for (final m in RegExp(
    r'INFOPLIST_KEY_(\w+) = "?([^";]*)"?;',
  ).allMatches(pbxText)) {
    present.putIfAbsent(m[1]!, () => m[2]!);
  }
  for (final f in project.files(
    sub: 'ios/Runner',
    where: (p) => p.endsWith('InfoPlist.strings'),
  )) {
    final text = _readStrings(f);
    for (final m in RegExp(
      r'''^\s*"?(\w+)"?\s*=\s*"((?:[^"\\]|\\.)*)"\s*;''',
      multiLine: true,
    ).allMatches(text)) {
      present.putIfAbsent(m[1]!, () => m[2]!);
    }
  }

  final deps =
      (project.pubspec['dependencies'] as YamlMap?)?.keys
          .map((k) => '$k')
          .toSet() ??
      {};
  final code = [
    for (final f in project.dartFiles('lib')) f.readAsStringSync(),
  ].join('\n');
  final needed = <String, Set<String>>{}; // "A|B" (any of) → who needs it
  for (final dep in deps) {
    for (final (anyOf, onlyIf)
        in pluginUsageKeys[dep] ?? const <(List<String>, String?)>[]) {
      if (onlyIf != null && !RegExp(onlyIf).hasMatch(code)) continue;
      needed.putIfAbsent(anyOf.join('|'), () => {}).add('`$dep`');
    }
  }
  if (deps.contains('permission_handler')) {
    final used = {
      for (final m in RegExp(r'\bPermission\.(\w+)').allMatches(code)) m[1]!,
    };
    for (final u in used) {
      final keys = permissionUsageKeys[u];
      if (keys != null) {
        needed.putIfAbsent(keys.join('|'), () => {}).add('`Permission.$u`');
      }
    }
  }

  for (final e in needed.entries) {
    final anyOf = e.key.split('|');
    final value = anyOf.map((k) => present[k]).nonNulls.firstOrNull;
    if (value == null || value.trim().isEmpty) {
      findings.add(
        Finding(
          id: 'ios.missing-purpose-string',
          area: Area.ios,
          severity: Severity.high,
          title:
              'Missing ${anyOf.first}${anyOf.length > 1 ? ' (or ${anyOf.skip(1).join(', ')})' : ''}, '
              'needed by ${e.value.join(', ')}',
          detail:
              'Without a purpose string iOS will not show the permission prompt: depending on '
              'the permission, the request fails or the app is terminated. App Store Connect '
              'also flags uploads whose code uses these APIs without one (ITMS-90683).',
          fix:
              'Add ${anyOf.first} to Info.plist with a sentence that says what the app does with '
              'the access, for example "Scan the QR code on your ticket."',
          locations: ['ios/Runner/Info.plist'],
        ),
      );
    }
  }

  // Purpose strings that exist but do not explain anything.
  final vague = <String>[];
  for (final e in present.entries) {
    if (!e.key.endsWith('UsageDescription')) continue;
    final v = e.value.trim();
    if (v.startsWith(r'$(')) continue; // filled in by a build setting
    if (v.isEmpty) {
      if (!needed.keys.any((k) => k.split('|').contains(e.key))) {
        vague.add('${e.key} (empty)');
      }
    } else if (_namesOnlyTheResource(v)) {
      vague.add('${e.key} ("$v")');
    }
  }
  if (vague.isNotEmpty) {
    findings.add(
      Finding(
        id: 'ios.vague-purpose-string',
        area: Area.ios,
        severity: Severity.medium,
        title:
            '${vague.length} purpose string${vague.length == 1 ? '' : 's'} too vague for App Review',
        detail:
            '${vague.join('; ')}. App Review rejects purpose strings that do not say how '
            'the app uses the data (guideline 5.1.1).',
        fix:
            'Say what the user gets, in a full sentence: "Take a photo of your receipt to '
            'attach it to the expense."',
        locations: ['ios/Runner/Info.plist'],
      ),
    );
  }
  return findings;
}

String _readStrings(File f) {
  final bytes = f.readAsBytesSync();
  // InfoPlist.strings is often UTF-16 with a BOM.
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    final le = bytes[0] == 0xFF;
    final units = <int>[
      for (var i = 2; i + 1 < bytes.length; i += 2)
        le ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1],
    ];
    return String.fromCharCodes(units);
  }
  return String.fromCharCodes(bytes);
}

List<Finding> _transportSecurity(Map<String, Object?> plist, String plistText) {
  final findings = <Finding>[];
  final ats = plist['NSAppTransportSecurity'];
  if (ats is! Map<String, Object?>) return findings;
  final at = plistText.indexOf('NSAllowsArbitraryLoads');
  final location =
      'ios/Runner/Info.plist${at < 0 ? '' : ':${lineOf(plistText, at)}'}';

  // iOS ignores NSAllowsArbitraryLoads when any of these is present.
  const overriding = [
    'NSAllowsArbitraryLoadsInWebContent',
    'NSAllowsArbitraryLoadsForMedia',
    'NSAllowsLocalNetworking',
  ];
  if (ats['NSAllowsArbitraryLoads'] == true &&
      !overriding.any(ats.containsKey)) {
    findings.add(
      Finding(
        id: 'security.ios-ats-disabled',
        area: Area.security,
        severity: Severity.high,
        title: 'App Transport Security is switched off',
        detail:
            'NSAllowsArbitraryLoads lets the app talk plain HTTP to any host, so traffic can '
            'be read and changed on the network. App Review also asks for a justification.',
        fix:
            'Remove NSAllowsArbitraryLoads and use HTTPS. If one host needs HTTP, add it '
            'under NSExceptionDomains instead.',
        locations: [location],
      ),
    );
  }
  final exceptions = ats['NSExceptionDomains'];
  if (exceptions is Map<String, Object?>) {
    final insecure = [
      for (final e in exceptions.entries)
        if (e.value is Map &&
            (e.value as Map)['NSExceptionAllowsInsecureHTTPLoads'] == true &&
            !RegExp(r'^(localhost|127\.0\.0\.1)$').hasMatch(e.key))
          e.key,
    ];
    if (insecure.isNotEmpty) {
      findings.add(
        Finding(
          id: 'security.ios-ats-exceptions',
          area: Area.security,
          severity: Severity.low,
          title: 'Plain HTTP allowed for ${insecure.join(', ')}',
          detail:
              'Traffic to these hosts can be read and changed on the network.',
          fix: 'Move them to HTTPS, or confirm they carry nothing sensitive.',
          locations: ['ios/Runner/Info.plist'],
        ),
      );
    }
  }
  return findings;
}

/// With CocoaPods, permission_handler compiles in only the permissions the
/// Podfile enables; the rest report denied without a prompt. (With Swift
/// Package Manager it reads Info.plist instead, which the purpose-string
/// check covers.)
List<Finding> _permissionHandlerMacros(FlutterProject project) {
  final deps =
      (project.pubspec['dependencies'] as YamlMap?)?.keys
          .map((k) => '$k')
          .toSet() ??
      {};
  final lock = project.file('ios/Podfile.lock');
  final podfile = project.file('ios/Podfile');
  if (!deps.contains('permission_handler') ||
      !lock.existsSync() ||
      !lock.readAsStringSync().contains('permission_handler_apple') ||
      !podfile.existsSync()) {
    return [];
  }
  final pod = stripRubyComments(podfile.readAsStringSync());
  final used = <String>{};
  for (final f in project.dartFiles('lib')) {
    for (final m in RegExp(
      r'\bPermission\.(\w+)',
    ).allMatches(f.readAsStringSync())) {
      used.add(m[1]!);
    }
  }
  final missing = <String, String>{}; // Permission.x → macro to add
  for (final u in used) {
    final macros = permissionMacros[u];
    if (macros == null) continue; // Android-only, or not a permission
    final enabled = macros.any(
      (m) => RegExp('\\b$m\\s*=\\s*1\\b').hasMatch(pod),
    );
    if (!enabled) {
      missing['Permission.$u'] = macros.last == 'PERMISSION_LOCATION_WHENINUSE'
          ? macros.last
          : macros.first;
    }
  }
  if (missing.isEmpty) return [];
  return [
    Finding(
      id: 'ios.permission-handler-disabled',
      area: Area.ios,
      severity: Severity.high,
      title:
          'permission_handler has ${missing.keys.map((k) => '`$k`').join(', ')} compiled out on iOS',
      detail:
          'The app installs permission_handler through CocoaPods, where every iOS permission '
          'is off unless the Podfile turns it on. These requests report denied without ever '
          'showing the prompt.',
      fix:
          'In ios/Podfile, add ${missing.values.toSet().map((m) => "'$m=1'").join(', ')} to '
          'GCC_PREPROCESSOR_DEFINITIONS in the post_install block (see the permission_handler '
          'README), then run pod install.',
      locations: ['ios/Podfile'],
    ),
  ];
}

/// Blanks `#` comments in a Podfile, outside strings.
String stripRubyComments(String ruby) => ruby
    .split('\n')
    .map((line) {
      var quote = '';
      for (var i = 0; i < line.length; i++) {
        final c = line[i];
        if (quote.isEmpty && (c == "'" || c == '"')) {
          quote = c;
        } else if (c == quote) {
          quote = '';
        } else if (quote.isEmpty && c == '#') {
          return line.substring(0, i);
        }
      }
      return line;
    })
    .join('\n');

/// "Camera access", "This app needs access to your location.": says what, not
/// why, which is the purpose string App Review sends back.
bool _namesOnlyTheResource(String v) =>
    RegExp(
      r'\b(todo|lorem|placeholder|description here)\b',
      caseSensitive: false,
    ).hasMatch(v) ||
    RegExp(
      r'^(?:(?:this|the)\s+)?(?:app\s+)?(?:needs|requires|uses|wants|would\s+like)?\s*(?:to\s+(?:access|use)\s+|access\s+(?:to\s+)?|permission\s+(?:to|for)\s+)?'
      r'(?:the\s+|your\s+)?(?:camera|photos?|photo\s+library|gallery|location|microphone|mic|contacts|calendars?|bluetooth|health\s+data|face\s*id|motion|speech\s+recognition|reminders|media\s+library)'
      r'(?:\s+(?:access|permission|usage|is\s+required|required|needed))?[.!]?$',
      caseSensitive: false,
    ).hasMatch(v.trim());
