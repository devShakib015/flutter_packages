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
