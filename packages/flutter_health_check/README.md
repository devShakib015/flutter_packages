# flutter_health_check

`fhc` audits a Flutter app the way a reviewer would before a release, and
writes one report ordered by what to fix first: Google Play and App Store
rules, leaked secrets, Firebase rules, vulnerable and stale packages, analyzer
results, tests and CI, and what the app bundles.

```bash
dart pub global activate flutter_health_check
cd path/to/app
fhc
```

```text
pulse: 74 / 100 (C)
  Dependencies              86  B
  Android & Google Play     69  C
  iOS & App Store          100  A
  Security & secrets       100  A
  Code health              100  A
  Tests & CI                72  C
  Assets & size            100  A

Fix first:
  [High] Release builds are signed with the debug key
  [High] No tests

Report: health-report.md, health-report.html
```

It reads the project's files, asks pub.dev and the OSV advisory database about
the locked packages, and runs `dart analyze`. It changes nothing in the project
unless you pass `--pub-get`.

## What it checks

**Dependencies.** Discontinued packages and their named replacements. Known
vulnerabilities in any locked package, direct or not (OSV). Packages two or more
breaking releases behind. Plugins with no release in two years (pure-Dart
packages are left alone: they are not what breaks when Android or iOS move).
Copyleft licences. Overrides, git dependencies without a `ref`, and path
dependencies outside the repository. Dependencies that nothing imports.

**Android and Google Play.** `targetSdk` against Play's current requirement
(API 36 since 31 August 2026). `minSdk`, Gradle, the Android Gradle Plugin and
Kotlin against the floors the installed Flutter enforces, read from the SDK
itself. The `com.example` application ID. Release builds signed with the debug
key. `android:debuggable`. Permissions Play restricts (all-files access,
`QUERY_ALL_PACKAGES`, SMS and call log, background location, package installs,
exact alarms, full-screen intents, photo and video access), Health Connect data
types, and foreground service types, each with what Play asks for.

**iOS and the App Store.** Purpose strings each plugin needs for what the app
actually uses (`ImageSource.camera` needs a camera string; picking from the
gallery needs none), including the ones permission_handler requests, found in
Info.plist, build settings or InfoPlist.strings. Purpose strings that name the
resource but not the reason. permission_handler permissions compiled out by the
Podfile. The UIScene life cycle that apps built with the iOS 27 SDK need to
launch (TN3187). App Transport Security switched off.

**Security.** Credentials with a recognisable shape (AWS, Stripe, OpenAI,
Anthropic, GitHub, Slack, SendGrid, Supabase service-role keys and more),
reported redacted so the report itself leaks nothing. Google API keys outside
Firebase config. `.env` files bundled as assets. Signing keys and
`key.properties` in git. Firestore, Storage and Realtime Database rules that are
open, in test mode, or open to any signed-in user. Cleartext HTTP, disabled
certificate checks, and plain `http://` URLs.

**Code, tests, assets.** Analyzer errors, warnings and deprecated API use. Lint
setup. Files over 800 lines. Tests (and whether the only one is the template's
counter test). CI, and whether it runs the tests. Heavy images, large bundled
files, and assets nothing refers to.

## Options

| | |
|---|---|
| `-o, --out` | Report path without extension (default `health-report`) |
| `-f, --format` | `md`, `html`, `json` (default `md,html`) |
| `--no-network` | Skip pub.dev and OSV |
| `--no-analyze` | Skip `dart analyze` |
| `--pub-get` | Run `flutter pub get` first if packages are not resolved |
| `--waive` | Report a finding id as accepted |
| `--fail-on` | Exit 1 at or above `critical`, `high`, `medium` or `low` (for CI) |

## In CI

```yaml
- run: dart pub global activate flutter_health_check
- run: fhc --fail-on high --format md,json
```

`--fail-on high` exits with 1 while a high or critical finding is open. The
JSON report carries every finding with its id, for whatever reads it next.

## Accepting a finding

Every finding has a stable id. List the ones the team has accepted in
`health_check.yaml` at the project root; they stay in the report, under
"Accepted by the project", and leave the score.

```yaml
waive:
  - id: android.debug-signing
    reason: CI signs the bundle with the upload key.
```

## The score

Each area starts at 100 and loses 40, 20, 8 or 3 points per critical, high,
medium or low finding. A critical caps its area at 39 (F) and a high at 74 (C).
The overall score is the average of the areas that could be checked, capped at
59 while anything is critical and 74 while anything is high, so one open
database cannot hide behind six clean areas.

## What it cannot see

Permissions that plugins merge into the Android manifest at build time, 16 KB
page-size support in native libraries, privacy-manifest problems App Store
Connect reports after upload, whether the store privacy answers match the SDKs,
runtime performance, and whether the architecture will hold up. The report
lists these at the end so a clean score is not mistaken for a clean app.

## Requirements

Dart 3.8 or later. `git`, to tell committed files from ignored ones. A Flutter
SDK on the `PATH` (or in `FLUTTER_ROOT`) for the checks that depend on what the
installed Flutter will build, and for `dart analyze`; without one, those are
listed under "Not checked" rather than passed. Network access to pub.dev and
osv.dev, or `--no-network`.

## From Dart

```dart
final report = await audit('path/to/app');
File('health-report.html').writeAsStringSync(toHtml(report));
```

`Report` holds the findings, the per-area scores and the facts; `toMarkdown`,
`toHtml` and `toJson` render it. See `example/`.

## Store rules

The rules the checks enforce live in `lib/src/facts.dart`, each with its date
and source. They change a few times a year; the tests pin them so a change is
deliberate.
