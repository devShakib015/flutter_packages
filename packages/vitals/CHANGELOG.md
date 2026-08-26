## 0.1.0

Initial release. iOS is complete; Android reads and aggregates but does not
yet write or delete.

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
