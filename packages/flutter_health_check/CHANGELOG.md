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
