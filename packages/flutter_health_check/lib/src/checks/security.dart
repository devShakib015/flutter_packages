import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../context.dart';
import '../model.dart';
import '../project.dart';
import '../text.dart';

class _Pattern {
  const _Pattern(this.name, this.re, this.severity);

  final String name;
  final String re;
  final Severity severity;
}

/// Credentials with a recognisable shape. Only formats that do not collide
/// with ordinary code: a false alarm here costs the report its credibility.
const secretPatterns = <_Pattern>[
  _Pattern(
    'AWS access key',
    r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b',
    Severity.critical,
  ),
  _Pattern(
    'private key',
    r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY(?: BLOCK)?-----',
    Severity.critical,
  ),
  _Pattern(
    'Stripe secret key',
    r'\b[rs]k_live_[0-9A-Za-z]{20,}',
    Severity.critical,
  ),
  _Pattern(
    'OpenAI API key',
    r'\bsk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_-]{16,}T3BlbkFJ[A-Za-z0-9_-]{16,}',
    Severity.critical,
  ),
  _Pattern(
    'Anthropic API key',
    r'\bsk-ant-(?:api|admin)\d{2}-[A-Za-z0-9_-]{80,}',
    Severity.critical,
  ),
  _Pattern(
    'GitHub token',
    r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})',
    Severity.critical,
  ),
  _Pattern(
    'SendGrid API key',
    r'\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}',
    Severity.critical,
  ),
  _Pattern(
    'Supabase secret key',
    r'\bsb_secret_[A-Za-z0-9_-]{20,}',
    Severity.critical,
  ),
  _Pattern('Slack token', r'\bxox[abprs]-[A-Za-z0-9-]{10,}', Severity.high),
  _Pattern(
    'Slack webhook',
    r'https://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+',
    Severity.high,
  ),
  _Pattern(
    'Firebase Cloud Messaging server key',
    r'\bAAAA[A-Za-z0-9_-]{7}:[A-Za-z0-9_-]{140}',
    Severity.high,
  ),
  _Pattern(
    'Google OAuth client secret',
    r'\bGOCSPX-[A-Za-z0-9_-]{28}',
    Severity.high,
  ),
  _Pattern(
    'Telegram bot token',
    r'\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b',
    Severity.high,
  ),
  _Pattern(
    'Mapbox secret token',
    r'\bsk\.eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}',
    Severity.high,
  ),
];

const _binary = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.icns',
  '.bmp',
  '.heic',
  '.ttf',
  '.otf',
  '.woff',
  '.woff2',
  '.mp3',
  '.mp4',
  '.m4a',
  '.mov',
  '.wav',
  '.ogg',
  '.aac',
  '.zip',
  '.gz',
  '.jar',
  '.aar',
  '.so',
  '.a',
  '.dylib',
  '.pdf',
  '.jks',
  '.keystore',
  '.p12',
  '.p8',
  '.mobileprovision',
  '.riv',
  '.db',
  '.sqlite',
  '.bin',
  '.apk',
  '.aab',
  '.ipa',
  '.xcframework',
  '.car',
  '.tflite',
  '.onnx',
  '.lock',
};

/// Secrets in tracked files and bundled assets, signing keys in git, Firebase
/// rules, and TLS or plain-HTTP shortcuts in the Dart code.
List<Finding> checkSecurity(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  final tracked = _gitFiles(project);
  final assets = project.declaredAssets;

  final candidates =
      <String>{
            ...(tracked ?? project.files().map((f) => project.rel(f.path))),
            ...assets,
          }
          .where((rel) => !_binary.contains(p.extension(rel).toLowerCase()))
          .toList()
        ..sort();
  if (tracked == null) {
    ctx.notes.add(
      'Not a git repository (or git is not installed), so every file was scanned '
      'for secrets and committed keystores could not be told apart from ignored ones.',
    );
  }

  final hits =
      <
        String,
        List<(String, String, Severity)>
      >{}; // name → (location, redacted, severity)
  final googleKeys = <String>[];
  var scanned = 0;
  for (final rel in candidates) {
    final file = project.file(rel);
    if (!file.existsSync()) continue;
    final size = file.lengthSync();
    if (size > 1536 * 1024) continue;
    final String text;
    try {
      text = file.readAsStringSync();
    } on FileSystemException {
      continue; // not UTF-8: treat as binary
    }
    scanned++;
    for (final pattern in secretPatterns) {
      for (final m in RegExp(pattern.re).allMatches(text)) {
        hits.putIfAbsent(pattern.name, () => []).add((
          '$rel:${lineOf(text, m.start)}',
          redact(m[0]!),
          pattern.severity,
        ));
      }
    }
    for (final m in RegExp(
      r'\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    ).allMatches(text)) {
      if (_jwtRole(m[0]!) == 'service_role') {
        hits.putIfAbsent('Supabase service_role key', () => []).add((
          '$rel:${lineOf(text, m.start)}',
          redact(m[0]!),
          Severity.critical,
        ));
      }
    }
    final isFirebaseConfig = RegExp(
      r'(^|/)(google-services\.json|GoogleService-Info\.plist|firebase_options[\w]*\.dart)$',
    ).hasMatch(rel);
    if (!isFirebaseConfig && (rel.startsWith('lib/') || assets.contains(rel))) {
      for (final m in RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b').allMatches(text)) {
        googleKeys.add('$rel:${lineOf(text, m.start)}');
      }
    }
  }
  ctx.facts['Files scanned for secrets'] = '$scanned';

  for (final e in hits.entries) {
    final ships = e.value.any((h) => _ships(h.$1, assets));
    findings.add(
      Finding(
        id: 'security.secret',
        area: Area.security,
        severity: e.value
            .map((h) => h.$3)
            .reduce((a, b) => a.index < b.index ? a : b),
        title:
            '${e.value.length == 1 ? 'A' : '${e.value.length}'} ${e.key}${e.value.length == 1 ? '' : 's'} '
            '${ships ? 'in code that ships with the app' : 'committed to the repository'}',
        detail:
            '${ships ? 'Anything inside the app can be extracted by anyone who downloads it. ' : 'Anyone with access to the repository, or to a leaked copy of it, can use it. '}'
            'Found: ${e.value.map((h) => h.$2).toSet().join(', ')} (shown redacted).',
        fix:
            'Revoke and rotate it now: removing it from the code does not un-leak it, and git '
            'history keeps it. Then move the call behind your own backend, or load the value '
            'from the CI environment for build-time use.',
        locations: [for (final h in e.value) h.$1],
      ),
    );
  }
  if (googleKeys.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.google-api-key',
        area: Area.security,
        severity: Severity.medium,
        title:
            'Google API key${googleKeys.length == 1 ? '' : 's'} in the app\'s Dart code or assets',
        detail:
            'Keys in the app can be extracted. That is expected for Firebase and Maps keys, '
            'which are safe only when restricted; it is a problem for billed APIs such as Gemini, '
            'Places or Translate, where anyone can spend your quota.',
        fix:
            'Check which API each key is for. Restrict Maps keys to your package name and '
            'signing certificate (and bundle ID) in Google Cloud Console. Call billed APIs from '
            'a backend, or through Firebase AI Logic with App Check.',
        locations: googleKeys,
      ),
    );
  }

  findings.addAll(_envFiles(project, tracked, assets));
  findings.addAll(_signingFiles(tracked));
  findings.addAll(_rules(ctx));
  findings.addAll(_dartNetwork(project));
  return findings;
}

/// First four and last two characters: enough to find the key, not enough to use it.
String redact(String secret) {
  final s = secret.replaceAll(RegExp(r'\s+'), ' ');
  if (s.startsWith('-----BEGIN')) return s;
  return s.length <= 10
      ? '${s.substring(0, 2)}…'
      : '${s.substring(0, 4)}…${s.substring(s.length - 2)}';
}

String? _jwtRole(String jwt) {
  try {
    var payload = jwt.split('.')[1].replaceAll('-', '+').replaceAll('_', '/');
    payload += '=' * ((4 - payload.length % 4) % 4);
    final json = jsonDecode(utf8.decode(base64.decode(payload)));
    return json is Map ? json['role']?.toString() : null;
  } catch (_) {
    return null;
  }
}

bool _ships(String location, Set<String> assets) {
  final rel = location.substring(0, location.lastIndexOf(':'));
  return assets.contains(rel) ||
      rel.startsWith('lib/') ||
      rel.startsWith('web/') ||
      rel.startsWith('android/app/src/main/') ||
      rel.startsWith('ios/Runner/');
}

/// Tracked files, relative to the project; null outside a git work tree.
/// Paths come from git relative to the working directory, so a symlinked
/// path (macOS's /var → /private/var) cannot make them disagree.
Set<String>? _gitFiles(FlutterProject project) {
  try {
    final r = Process.runSync('git', [
      'ls-files',
      '-z',
      '.',
    ], workingDirectory: project.root.path);
    if (r.exitCode != 0) return null;
    return {
      for (final f in (r.stdout as String).split('\x00'))
        if (f.isNotEmpty) f,
    };
  } on ProcessException {
    return null;
  }
}

List<Finding> _envFiles(
  FlutterProject project,
  Set<String>? tracked,
  Set<String> assets,
) {
  final findings = <Finding>[];
  bool isEnv(String rel) {
    final name = p.basename(rel);
    return (name == '.env' || name.startsWith('.env.')) &&
        !RegExp(r'\.(example|sample|template|dist)$').hasMatch(name);
  }

  final bundled = assets.where(isEnv).toList();
  if (bundled.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.env-in-assets',
        area: Area.security,
        severity: Severity.high,
        title: '${bundled.join(', ')} is bundled into the app as an asset',
        detail:
            'flutter_dotenv reads its file from the app\'s assets, so every value in it '
            'ships inside the APK and IPA, readable by anyone who unzips them. It works for '
            'configuration, not for secrets.',
        fix:
            'Keep only public configuration there. Move secrets to a backend; for build-time '
            'values use --dart-define-from-file with a file that is not an asset (they still end '
            'up in the binary, so nothing secret).',
        locations: ['pubspec.yaml'],
      ),
    );
  }
  final committed = (tracked ?? const <String>{}).where(isEnv).where((rel) {
    final f = project.file(rel);
    return f.existsSync() &&
        RegExp(
          r'^\s*\w+\s*=\s*\S',
          multiLine: true,
        ).hasMatch(f.readAsStringSync());
  }).toList();
  if (committed.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.env-committed',
        area: Area.security,
        severity: Severity.medium,
        title: '${committed.join(', ')} is committed to git',
        detail:
            'Environment files usually hold credentials. Once committed they stay in the '
            'history even after the file is deleted.',
        fix:
            'Add it to .gitignore, commit a .env.example with the keys and no values, and '
            'rotate anything secret it contained.',
        locations: committed,
      ),
    );
  }
  return findings;
}

List<Finding> _signingFiles(Set<String>? tracked) {
  if (tracked == null) return [];
  final findings = <Finding>[];
  final properties = tracked
      .where((f) => p.basename(f) == 'key.properties')
      .toList();
  if (properties.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.key-properties-committed',
        area: Area.security,
        severity: Severity.critical,
        title: 'The Android signing passwords (key.properties) are in git',
        detail:
            'key.properties holds the keystore and key passwords. With the keystore, they are '
            'everything needed to sign an update as you.',
        fix:
            'Remove it from git and add it to .gitignore. Change the passwords; if the keystore '
            'is also committed, ask Google Play support to reset the upload key.',
        locations: properties,
      ),
    );
  }
  final keystores = tracked
      .where(
        (f) =>
            RegExp(r'\.(jks|keystore)$').hasMatch(f) &&
            p.basename(f) != 'debug.keystore',
      )
      .toList();
  if (keystores.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.keystore-committed',
        area: Area.security,
        severity: Severity.high,
        title:
            'Signing keystore${keystores.length == 1 ? '' : 's'} committed: ${keystores.join(', ')}',
        detail:
            'Anyone with the repository has the key; only its password stands between them '
            'and signing updates as you.',
        fix:
            'Remove it from git (and its history), keep it in a password manager or CI secret, '
            'and ask Google Play support to reset the upload key.',
        locations: keystores,
      ),
    );
  }
  final appleKeys = tracked
      .where((f) => RegExp(r'\.(p8|p12)$').hasMatch(f))
      .toList();
  if (appleKeys.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.apple-key-committed',
        area: Area.security,
        severity: Severity.critical,
        title:
            'Apple key or certificate file committed: ${appleKeys.join(', ')}',
        detail:
            '.p8 files are App Store Connect API or push keys; .p12 files hold signing '
            'certificates with their private keys.',
        fix:
            'Revoke the key or certificate in the Apple Developer portal, issue a new one, '
            'and keep it in CI secrets.',
        locations: appleKeys,
      ),
    );
  }
  return findings;
}

List<Finding> _rules(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  final files = <String>{
    'firestore.rules',
    'storage.rules',
    'database.rules.json',
  };
  final firebaseJson = project.file('firebase.json');
  if (firebaseJson.existsSync()) {
    try {
      final json = jsonDecode(firebaseJson.readAsStringSync());
      void add(Object? v) {
        if (v is Map && v['rules'] is String) files.add(v['rules'] as String);
        if (v is List) v.forEach(add);
      }

      if (json is Map) {
        add(json['firestore']);
        add(json['storage']);
        add(json['database']);
      }
    } on FormatException {
      // Not our problem to report; the Firebase CLI will.
    }
  }
  final found = files.where((f) => project.file(f).existsSync()).toList()
    ..sort();
  if (found.isNotEmpty) ctx.facts['Firebase rules files'] = found.join(', ');

  for (final rel in found) {
    final raw = project.file(rel).readAsStringSync();
    if (rel.endsWith('.json')) {
      findings.addAll(_databaseRules(rel, raw));
      continue;
    }
    final code = stripComments(raw);
    final open = <String>[], authOnly = <String>[], testMode = <String>[];

    // Recursive wildcards (`match /{document=**}`) cover every path below them.
    final wildcard = <(int, int)>[];
    for (final m in RegExp(r'match\s+/\{\w+=\*\*\}\s*').allMatches(code)) {
      final b = block(code, RegExp(RegExp.escape(m[0]!)), m.start);
      if (b != null) wildcard.add(b);
    }
    bool inWildcard(int offset) =>
        wildcard.any((b) => offset >= b.$1 && offset < b.$2);

    for (final m in RegExp(
      r'allow\s+([\w\s,]+?)\s*(?::\s*if\s+([^;]+))?;',
    ).allMatches(code)) {
      final methods = m[1]!.split(',').map((s) => s.trim()).toList();
      final condition = m[2]?.trim().replaceAll(RegExp(r'\s+'), ' ');
      final writes = methods.any(
        (x) => const {'write', 'create', 'update', 'delete'}.contains(x),
      );
      final at = '$rel:${lineOf(code, m.start)}';
      if (condition == null || condition == 'true') {
        if (writes || inWildcard(m.start)) open.add(at);
      } else if (RegExp(
        r'^request\.time\s*<\s*timestamp\.date\(',
      ).hasMatch(condition)) {
        testMode.add(at);
      } else if (inWildcard(m.start) &&
          RegExp(r'^request\.auth\s*!=\s*null$').hasMatch(condition)) {
        authOnly.add(at);
      }
    }
    final kind = rel.contains('storage') ? 'Storage' : 'Firestore';
    if (open.isNotEmpty) {
      findings.add(
        Finding(
          id: 'security.rules-open',
          area: Area.security,
          severity: Severity.critical,
          title:
              '$kind rules let anyone ${open.length == 1 ? 'in' : 'in (${open.length} places)'}',
          detail:
              'A rule with no condition, or `if true`, lets anyone on the internet read or '
              'write with nothing but your public Firebase config, without using the app at all.',
          fix:
              'Require request.auth and check it against the document (for example '
              'request.auth.uid == userId), and validate what is written. ds_rules, a Firestore '
              'rules linter for VS Code, flags these as you type.',
          locations: open,
        ),
      );
    }
    if (testMode.isNotEmpty) {
      findings.add(
        Finding(
          id: 'security.rules-test-mode',
          area: Area.security,
          severity: Severity.critical,
          title: '$kind rules are still in test mode',
          detail:
              'Test-mode rules let anyone read and write everything until a date, then deny '
              'everything, which breaks the app on that day.',
          fix:
              'Replace them with rules that check request.auth and the data being written.',
          locations: testMode,
        ),
      );
    }
    if (authOnly.isNotEmpty) {
      findings.add(
        Finding(
          id: 'security.rules-any-user',
          area: Area.security,
          severity: Severity.high,
          title:
              'Any signed-in user can reach every $kind ${kind == 'Storage' ? 'file' : 'document'}',
          detail:
              '`request.auth != null` on a recursive wildcard lets one user read or overwrite '
              'every other user\'s data. With anonymous or open sign-up, that is anyone.',
          fix:
              'Write rules per collection that check ownership, such as '
              'request.auth.uid == resource.data.ownerId.',
          locations: authOnly,
        ),
      );
    }
  }
  return findings;
}

List<Finding> _databaseRules(String rel, String raw) {
  final code = stripComments(raw);
  Object? json;
  try {
    json = jsonDecode(code);
  } on FormatException {
    return [];
  }
  final rules = json is Map ? json['rules'] : null;
  if (rules is! Map) return [];
  final findings = <Finding>[];
  for (final access in ['.read', '.write']) {
    final v = rules[access];
    final condition = v is String ? v.replaceAll(RegExp(r'\s+'), '') : v;
    final open = condition == true || condition == 'true';
    final anyUser = condition == 'auth!=null';
    if (!open && !anyUser) continue;
    final at = RegExp('"${RegExp.escape(access)}"').firstMatch(code);
    findings.add(
      Finding(
        id: open ? 'security.rules-open' : 'security.rules-any-user',
        area: Area.security,
        severity: open ? Severity.critical : Severity.high,
        title:
            'Realtime Database rules give ${open ? 'anyone' : 'any signed-in user'} '
            '${access.substring(1)} access to the whole database',
        detail:
            'A rule at the root applies to every path below it and cannot be narrowed by '
            'rules deeper down.',
        fix:
            'Remove the root rule and grant access per path, checking auth.uid against the data.',
        locations: ['$rel${at == null ? '' : ':${lineOf(code, at.start)}'}'],
      ),
    );
  }
  return findings;
}

List<Finding> _dartNetwork(FlutterProject project) {
  final findings = <Finding>[];
  final bypass = <String>[], plain = <String, String>{};
  final private = RegExp(
    r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.0\.0\.0|[\w-]+\.local$)',
  );
  const ignoredHosts = {
    'www.w3.org',
    'schemas.android.com',
    'schemas.xmlsoap.org',
    'example.com',
    'www.example.com',
    'example.org',
    'ns.adobe.com',
    'purl.org',
    'xmlns.com',
  };
  for (final f in project.dartFiles('lib')) {
    final rel = project.rel(f.path);
    final text = f.readAsStringSync();
    for (final m in RegExp(
      r'badCertificateCallback\s*=\s*\([^)]*\)\s*(?:=>\s*true|\{\s*return\s+true\s*;\s*\})',
    ).allMatches(text)) {
      bypass.add('$rel:${lineOf(text, m.start)}');
    }
    for (final m in RegExp(
      r'''['"]http://([A-Za-z0-9.-]+\.[A-Za-z]{2,}|\d+\.\d+\.\d+\.\d+)''',
    ).allMatches(text)) {
      final host = m[1]!;
      if (private.hasMatch(host) || ignoredHosts.contains(host)) continue;
      plain.putIfAbsent(host, () => '$rel:${lineOf(text, m.start)}');
    }
  }
  if (bypass.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.tls-bypass',
        area: Area.security,
        severity: Severity.high,
        title: 'Certificate checks are switched off for HTTPS',
        detail:
            'A badCertificateCallback that returns true accepts any certificate, so anyone '
            'on the network can impersonate your server and read the traffic.',
        fix:
            'Remove it. If it exists for a self-signed dev server, limit it to that host and to '
            'debug builds (kDebugMode).',
        locations: bypass,
      ),
    );
  }
  if (plain.isNotEmpty) {
    findings.add(
      Finding(
        id: 'security.plain-http-urls',
        area: Area.security,
        severity: Severity.low,
        title:
            'Plain http:// URLs for ${plain.length} host${plain.length == 1 ? '' : 's'}: '
            '${plain.keys.take(5).join(', ')}${plain.length > 5 ? ', …' : ''}',
        detail:
            'Android and iOS block plain HTTP by default, so these calls either fail or '
            'only work because the block was switched off.',
        fix: 'Use https:// for each host.',
        locations: plain.values.toList(),
      ),
    );
  }
  return findings;
}
