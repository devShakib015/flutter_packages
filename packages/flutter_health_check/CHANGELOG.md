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
