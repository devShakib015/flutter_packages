import 'dart:convert';

import 'package:flutter_health_check/flutter_health_check.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // Built at runtime so this file never contains a string that looks like a
  // real credential (and trips a scanner, this one included).
  final aws = 'AKIA${'Q' * 12}WXYZ';
  final googleKey = 'AIza${'b' * 35}';
  String b64(String s) => base64Url.encode(utf8.encode(s)).replaceAll('=', '');
  String jwt(String role) =>
      '${b64('{"alg":"HS256","typ":"JWT"}')}.${b64('{"iss":"supabase","role":"$role"}')}.${'s' * 43}';

  test(
    'a key in the Dart code ships with the app, and is shown redacted',
    () async {
      final r = await check(
        project({...healthy(), 'lib/api.dart': "const key = '$aws';\n"}),
      );
      final f = one(r, 'security.secret');
      expect(f.severity, Severity.critical);
      expect(f.title, contains('ships with the app'));
      expect(f.locations.single, 'lib/api.dart:1');
      expect(toMarkdown(r), isNot(contains(aws)));
      expect(toHtml(r), isNot(contains(aws)));
      expect(f.detail, contains('AKIA…YZ'));
    },
  );

  test(
    'Google keys: expected in Firebase config, reported elsewhere in lib/',
    () async {
      final clean = await check(
        project({
          ...healthy(),
          'lib/firebase_options.dart': "const apiKey = '$googleKey';\n",
        }),
      );
      expect(ids(clean), isNot(contains('security.google-api-key')));
      final r = await check(
        project({
          ...healthy(),
          'lib/gemini.dart': "const apiKey = '$googleKey';\n",
        }),
      );
      expect(one(r, 'security.google-api-key').severity, Severity.medium);
    },
  );

  test(
    'Supabase: service_role is critical, anon is public by design',
    () async {
      final anon = await check(
        project({
          ...healthy(),
          'lib/supabase.dart': "const key = '${jwt('anon')}';\n",
        }),
      );
      expect(ids(anon), isNot(contains('security.secret')));
      final service = await check(
        project({
          ...healthy(),
          'lib/supabase.dart': "const key = '${jwt('service_role')}';\n",
        }),
      );
      expect(
        one(service, 'security.secret').title,
        contains('Supabase service_role key'),
      );
    },
  );

  test('.env bundled as an asset', () async {
    final r = await check(
      project({
        ...healthy(),
        'pubspec.yaml': '$pubspec\nflutter:\n  assets:\n    - .env\n',
        '.env': 'API_URL=https://api.example.net\n',
      }),
    );
    expect(one(r, 'security.env-in-assets').severity, Severity.high);
  });

  group('tracked files', () {
    test('key.properties and keystores in git; .env.example is fine', () async {
      final dir = project({
        ...healthy(),
        'android/key.properties':
            'storePassword=hunter2\nkeyPassword=hunter2\n',
        'android/app/upload.jks': 'binary',
        '.env': 'TOKEN=abc\n',
        '.env.example': 'TOKEN=\n',
      });
      git(dir, ['init', '-q']);
      git(dir, ['add', '-A']);
      final r = await check(dir);
      expect(
        one(r, 'security.key-properties-committed').severity,
        Severity.critical,
      );
      expect(
        one(r, 'security.keystore-committed').title,
        contains('android/app/upload.jks'),
      );
      expect(one(r, 'security.env-committed').title, startsWith('.env '));
    });

    test('an ignored secret file is not reported', () async {
      final dir = project({
        ...healthy(),
        '.gitignore': 'android/key.properties\n',
        'android/key.properties': 'storePassword=x\n',
      });
      git(dir, ['init', '-q']);
      git(dir, ['add', '-A']);
      expect(
        ids(await check(dir)),
        isNot(contains('security.key-properties-committed')),
      );
    });
  });

  group('Firebase rules', () {
    Future<Report> rules(String firestore) =>
        check(project({...healthy(), 'firestore.rules': firestore}));

    test('open to anyone', () async {
      final r = await rules('''
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}''');
      expect(
        one(r, 'security.rules-open').locations.single,
        'firestore.rules:5',
      );
    });

    test('world-readable everything', () async {
      final r = await rules('''
service cloud.firestore {
  match /databases/{database}/documents {
    match /{path=**} {
      allow read;
      allow write: if request.auth.uid == 'admin';
    }
  }
}''');
      expect(
        one(r, 'security.rules-open').locations.single,
        'firestore.rules:4',
      );
    });

    test('test mode', () async {
      final r = await rules('''
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.time < timestamp.date(2026, 10, 1);
    }
  }
}''');
      expect(ids(r), contains('security.rules-test-mode'));
    });

    test(
      'any signed-in user on the wildcard; public reads of one collection are fine',
      () async {
        final r = await rules('''
service cloud.firestore {
  match /databases/{database}/documents {
    match /products/{id} {
      allow read: if true;
    }
    // allow write: if true;
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}''');
        expect(ids(r), {'security.rules-any-user'});
      },
    );

    test('Realtime Database root rules', () async {
      final r = await check(
        project({
          ...healthy(),
          'database.rules.json':
              '{"rules": {".read": "auth != null", ".write": true}}',
        }),
      );
      expect(ids(r), {'security.rules-open', 'security.rules-any-user'});
    });
  });

  test('TLS bypass and plain HTTP in Dart', () async {
    final r = await check(
      project({
        ...healthy(),
        'lib/net.dart': '''
class Overrides extends HttpOverrides {
  HttpClient createHttpClient(SecurityContext? c) =>
      super.createHttpClient(c)..badCertificateCallback = (cert, host, port) => true;
}
const api = 'http://api.shop.example.net/v1';
const local = 'http://10.0.2.2:8080';
const ns = 'http://www.w3.org/2000/svg';
''',
      }),
    );
    expect(one(r, 'security.tls-bypass').severity, Severity.high);
    expect(
      one(r, 'security.plain-http-urls').title,
      allOf(
        contains('api.shop.example.net'),
        isNot(contains('10.0.2.2')),
        isNot(contains('w3.org')),
      ),
    );
  });
}
