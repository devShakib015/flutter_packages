## 0.3.1

Fixes the Android build. 0.3.0's permission-flow fix called a `fail` helper
that exists on the Swift side but not in the Kotlin, so the plugin did not
compile for Android — this machine cannot run the Android toolchain and CI
caught it after the release. Use this rather than 0.3.0.

## 0.3.0

An audit of every package in this repo found six defects here. Two of them
made Android unusable for what it claimed to do.

### Fixed

- **Health Connect looked "not installed" on Android 11-13.** The plugin's
  manifest had no `<queries>` entry, and Android 11 introduced package
  visibility filtering — so `isAvailable()` could not see Health Connect on
  the versions where it ships as a separate APK, and reported false on a
  device where it was installed and working. Declared in the plugin's own
  manifest, so it merges into every consuming app.
- **`writeVolume` always threw on Android.** The Dart signature takes a single
  instant, so start and end were equal, and `HydrationRecord` rejects a
  zero-length window. Every water write failed. Interval records now widen a
  zero-length window by a millisecond.
- **Reads were silently truncated at 1000 records.** Health Connect caps a
  response and hands back a `pageToken`; nothing followed it. A month of step
  data came back short, statistics were computed from a partial series, and
  `delete` removed only the first thousand matches and reported that as the
  count. All three paths paginate now.
- **A failed permission launch wedged the flow permanently.** `pendingResult`
  was cleared only on a successful activity result, so if the launch threw —
  or the activity or engine detached first — the Dart future never completed
  and every later request was refused as already in progress. It resolves on
  every path now, and a configuration change deliberately does not abandon a
  live request.
- **iOS returned a sum labelled as an average.** For a cumulative type,
  `statistics()` used `.cumulativeSum` whatever aggregate was asked for, so
  asking for the average of daily steps got the total with a confident wrong
  name. It refuses now, as `UnsupportedVitalTypeException`, rather than
  answering wrongly.

### Known, not fixed

- Android flattens a sleep session to a single `asleep` reading rather than
  emitting its stages, and `statistics()` returns an all-null series for sleep
  and workout. iOS reports stages correctly.

## 0.2.0

**Writing is verified on iOS.** 250 ml of water written and read back at the
same value and unit, end to end.

Previous versions said writing had never been observed to work and suggested
the iOS Simulator might be at fault. That was wrong, and the fault was here:
this package's own example had a `Runner.entitlements` file that was never
referenced by its Xcode project — `CODE_SIGN_ENTITLEMENTS` was absent — so the
app was built with no HealthKit entitlement and every write was refused. The
package's write path was correct the whole time.

The iOS setup section now warns about it, because adding the file by hand
without wiring it in is an easy mistake and produces exactly this symptom:
builds fine, reads look fine, every write returns *Not authorized*.

**The write documentation described an API that does not exist.** 0.1.2 showed
`writeMass(type, 71.2, unit: Mass.kilograms)` and `writeCount(..., at:)`.
Neither is real — the unit is carried by the value type, and counts take a
period rather than an instant. Every snippet in that section is now compiled
against the real API by `test/readme_examples_test.dart`, so a wrong signature
fails the suite instead of reaching a reader.

- Adds a screenshot of the verified write.
- Adds `example/integration_test/write_roundtrip_test.dart`, which asserts the
  value that comes back as well as the count — a unit-conversion mistake would
  otherwise be silent.

**Android is still unverified.** The Health Connect round trip has not been run.

## 0.1.2

Documentation only — no API changes.

- **Writing is now documented at all.** The package has seven write methods and
  the README showed none of them, so the only way to discover how to write a
  sample was to read the source. There is a section for it now, with the table
  mapping each `VitalType<T>` to the method that accepts it.
- That mapping turns out to be the nicest thing about the write API and was
  entirely invisible: the types are generic, so `writeMass(VitalType.steps, …)`
  does not compile. The compiler picks the method for you. Worth saying out
  loud.
- The README's examples used `Vitals.instance` in the first snippet and a bare
  `vitals` in later ones, with nothing introducing it. They all use
  `Vitals.instance` now.

## 0.1.1

Packaging only — no API or behaviour changes.

- Added `.pubignore`. Previous versions shipped the package's own `test/`
  directory and the example's integration tests to everyone who depended on it.

## 0.1.0

Initial release.

**Reading is verified; writing is not.** Reads are exercised against a real
HealthKit store. Writes compile on both platforms but have not been observed to
succeed end to end — the iOS Simulator rejects `save` as unauthorised even
after the sheet is granted, and the Android round trip is unrun. Verify written
values land correctly before relying on them.

### Typed throughout
- `VitalType<T>` carries the Dart type it reads back as, so `read(VitalType.steps)`
  returns `List<CountSample>` and `read(VitalType.bodyMass)` returns
  `List<MassSample>`. No casting, no codegen.
- `Mass`, `Length`, `Energy`, `Volume`, `Temperature`, `Pressure` and
  `Concentration` store one canonical value with named accessors.
- 21 vital types, each declaring the aggregation that suits it.

### Permissions, modelled on what the platforms can actually answer
- No `readAccess()`. `HKAuthorizationStatus` has three values and all three
  describe *sharing*; iOS cannot report read access by design.
- `readAccessOnAndroid()` returns null on iOS rather than guessing.
- `AuthorizationNotDeterminedException` covers the one state iOS *does*
  report: a query made before the user was ever asked.

### Statistics
- Hourly, daily, weekly and monthly buckets, reduced on the platform side.
- A bucket with no samples reports null, not zero.

### Testing
- `FakeVitals` runs the whole API in memory, including an ineligible device, a
  refused sheet, and the iOS silent read denial.
