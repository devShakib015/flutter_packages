## 0.3.0

**The eMudhra certificates.** Compromised eMudhra certificate authorities can
forge HTTPS certificates, and builds that compile in the old roots keep trusting
them whatever the operating system does. No package database lists this for
Flutter's SDK or for `cloud_firestore`, so `deps.vulnerability` stays silent, and
three new findings read it directly. `security.emudhra-flutter` flags Flutter
below 3.47.8 (3.50.0-0.2.pre on beta) on Android, Windows and Linux, reading the
version from the project's pin and its CI, including composite actions.
`security.emudhra-firestore` flags `cloud_firestore` on iOS, macOS and Windows:
6.10.1 fixed only Apple's platforms, and 7.0.0 fixed neither, so the version
alone isn't the answer. `security.emudhra-app-distribution` flags the Firebase
App Distribution Gradle plugin. The first two are High, because installed builds
stay exposed until users update. With no pin, the Flutter on the machine running
`fhc` is all there is to go on, so that case is Medium and says so.

**Google Play's 2027 permission rules.** `ACCESS_FINE_LOCATION`, `READ_CONTACTS`,
`WRITE_CONTACTS`, `MANAGE_CONTACTS` and `ACCESS_LOCAL_NETWORK` are now reported
with what Play asks for and when (27 January and 25 August 2027). They are Low
for now, because they apply once an app targets API 37 or 38. A fine-location
entry with `onlyForLocationButton` is what Play wants, so it isn't reported.
`READ_CALL_LOG` adds that verifying an account by phone call stops being allowed.

**Removed.** `StoreRules.playExtensionUntil`, and the sentence about extensions:
the last one ended on 1 November 2026.

**Two fixes.** `toJson` now lists the `skipped` areas. In print, the report's
severity bar kept the card's grey border instead of its severity colour.

**Checked on real apps first.** Three open-source apps and two of the author's.
One keeps its Flutter pin in a composite action, which the first version missed.
Another builds Flutter from a git submodule, where the Flutter on this machine
says nothing about the release, so that is now a note instead of a finding.

## 0.2.0

**Plugin readiness for Swift Package Manager and AGP 9.** Two new findings, read
from the versions the lockfile resolved rather than pub.dev's latest:
`ios.cocoapods-only` for plugins with no Swift package, which Flutter builds
through CocoaPods (read-only from 2 December 2026), with the newer release that
has one when pub.dev knows of it; and `android.kotlin-gradle-plugin` for plugins
whose Android build applies the Kotlin Gradle Plugin, which AGP 9's built-in
Kotlin refuses. That one is High once `android.builtInKotlin=true`, because the
build then fails. A federated plugin is named with the dependency that pulls it
in (`url_launcher_ios` via `url_launcher`), and dev_dependencies are left out.

**Checked on real apps first.** LocalSend, Saber, wger and two of the author's
apps. wger caught a false positive: health_bridge and sentry_flutter apply
`kotlin-android` only below AGP 9 (`if (!isAgp9OrAbove)`, `if (!builtInKotlin)`),
which builds fine with built-in Kotlin on. An application inside an `if` about
the AGP version or built-in Kotlin now counts as migrated, and is a test.

## 0.1.0

First release. `fhc` reads a Flutter project and writes one report, scored by
area and ordered by what to fix first: Google Play and App Store requirements,
leaked secrets and Firebase rules, vulnerable, discontinued and stale packages,
analyzer results, tests and CI, and bundled assets.

**Checked against real apps before release, not only fixtures.** Six of the
author's apps and two open-source ones (localsend and wger) turned up four
false positives, and each is now a test. image_picker asked for camera and
photo-library purpose strings that apps which never open the camera ship
without. Packages imported only from generated code counted as unused. A Flutter
version pinned at the repository root was missed for an app in a subfolder. And
a purpose string was called vague for being short, rather than for failing to
say why.

**The Dart floor is 3.8** (Flutter 3.32), for null-aware collection elements.
Checked against a real 3.8.0 SDK: everything resolves, and the whole suite
passes. CI repeats the run on every push.
