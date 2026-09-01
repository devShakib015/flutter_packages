# vitals

Type-safe access to Apple Health and Health Connect.

```dart
final steps = await Vitals.instance.read(
  VitalType.steps,
  from: weekAgo,
  to: now,
);
// List<CountSample> — steps.first.count is an int.
```

> **Status.**
>
> **Reading is verified** against a real HealthKit store, and the Dart contract
> has a full unit-test suite behind it.
>
> **Writing is verified on iOS**, end to end: 250 ml of water written and read
> back at the same value and unit. Earlier versions of this file said writing
> had never been observed to work and blamed the Simulator. That was wrong —
> the fault was in this package's own example, whose entitlements file was
> never wired into its Xcode project, so the app was built without the
> HealthKit entitlement and every write was refused. See
> [iOS setup](#ios-setup); it is an easy mistake to repeat.
>
> **Android is still unverified.** The Health Connect round trip has not been
> run. If you write on Android, check the values land before trusting them — a
> unit-conversion mistake would be silent, and health records are awkward to
> correct.

![The example writing a sample and reading it back](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/vitals/doc/write_verified.png)

## Why another one

`health` is the established package, it is actively maintained, and it covers
more data types than this does. If you need breadth today, use it. This exists
for three things it does not do.

**Nothing is cast.** The type you ask for decides the type you get back:

```dart
final weight = await Vitals.instance.read(VitalType.bodyMass, from: a, to: b);
weight.first.value.pounds;   // a Mass, not a double you hope is kilograms
```

**Permissions are modelled on what the platforms can actually answer.** There
is deliberately no `readAccess()`, because `HKAuthorizationStatus` has exactly
three values and all three describe *writing*:

```c
HKAuthorizationStatusNotDetermined
HKAuthorizationStatusSharingDenied
HKAuthorizationStatusSharingAuthorized
```

Apple omits read status on purpose — knowing which health types someone has
recorded would itself disclose health information. So any API that answers
"do I have read permission?" is guessing on iOS. This one doesn't ask.

**Health flows are testable.** `FakeVitals` runs the entire API in memory.

## The three permission states

Running against a real store turned up something worth encoding: HealthKit
distinguishes *never asked* from *asked and refused*, and only the second is
silent.

| State | What a read does |
| --- | --- |
| Never requested | throws `AuthorizationNotDeterminedException` |
| Requested, granted | returns data |
| Requested, refused | returns **empty** — indistinguishable from no data |

So the exception means your app forgot to call `requestPermissions`, which is a
bug you can fix. Emptiness afterwards is genuinely ambiguous, on every package,
forever. Write your UI accordingly:

```dart
switch (await Vitals.instance.readAccessOnAndroid({VitalType.steps})) {
  case null:            // iOS: unknowable, attempt the read and handle empty
  case final access:    // Android: an actual answer
}
```

## Writing

There is one method per kind of quantity, and **the compiler picks it for
you** — each `VitalType` is generic over its sample type, so a mismatch does
not compile:

```dart
await vitals.writeMass(VitalType.steps, const Mass.kilograms(71.2), at: now);
// error: VitalType<CountSample> can't be assigned to VitalType<MassSample>
```

The unit is part of the value rather than a separate argument, so there is no
way to pass kilograms and mean pounds:

```dart
await vitals.writeMass(VitalType.bodyMass, const Mass.kilograms(71.2), at: now);
await vitals.writeVolume(VitalType.water, const Volume.millilitres(250), at: now);
```

Some quantities happen at an instant, others accumulate over a period, and the
signature says which:

```dart
// over a period
await vitals.writeCount(VitalType.steps, 2400, from: earlier, to: now);
await vitals.writeLength(
  VitalType.distanceWalkingRunning, const Length.metres(1800),
  from: earlier, to: now,
);

// at an instant
await vitals.writeRate(VitalType.heartRate, 62, at: now);
await vitals.writePercent(VitalType.oxygenSaturation, 0.98, at: now);
```

| the type you have | the method | the value |
| --- | --- | --- |
| `VitalType<CountSample>` | `writeCount` | `int`, over a period |
| `VitalType<MassSample>` | `writeMass` | `Mass`, at an instant |
| `VitalType<LengthSample>` | `writeLength` | `Length`, over a period |
| `VitalType<EnergySample>` | `writeEnergy` | `Energy`, over a period |
| `VitalType<RateSample>` | `writeRate` | `double` per minute, at an instant |
| `VitalType<PercentSample>` | `writePercent` | `double` fraction, at an instant |
| `VitalType<VolumeSample>` | `writeVolume` | `Volume`, at an instant |

Every snippet above is compiled against the real API by
`test/readme_examples_test.dart`, because the previous version of this section
documented signatures that did not exist.

## Statistics, not raw samples

A year of heart-rate readings is hundreds of thousands of points. Reducing them
on the platform beats shipping them across the channel:

```dart
final daily = await Vitals.instance.statistics(
  VitalType.steps,
  from: monthAgo,
  to: now,
  bucket: VitalBucket.daily,
);
```

Each type knows how it should be reduced — steps sum, heart rate averages,
weight takes the latest — so you rarely pass `aggregate` yourself. A bucket
with no samples reports `null`, never `0`; conflating those is how averages go
wrong.

## Testing

```dart
final vitals = FakeVitals()
  ..seedCounts(VitalType.steps, {
    DateTime(2026, 8, 24): 8210,
    DateTime(2026, 8, 25): 11430,
  });
```

It models the awkward states too, not just the happy path:

```dart
FakeVitals(available: false);              // ineligible device
FakeVitals(permissionSheetSucceeds: false); // user dismissed the sheet
FakeVitals(readsAreBlocked: true);          // the iOS silent denial
```

## iOS setup

Three things, all required, none of them optional:

**1. Add the HealthKit capability** in Xcode, or an entitlements file:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
```

**2. Add both usage descriptions** to `Info.plist`. Omitting either crashes the
app the moment you request that kind of access:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Why you read health data.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Why you write health data.</string>
```

**3. Minimum iOS 15.** Sleep stages finer than "asleep" and workout totals need
iOS 16; below that they degrade rather than failing.


**Wire the entitlements file into the project, not just into the folder.**
Adding the capability through Xcode's *Signing & Capabilities* tab does this
for you. If you create `Runner.entitlements` by hand — or copy one in — you
must also set `CODE_SIGN_ENTITLEMENTS` in the build settings, or the file is
simply ignored:

```
CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
```

Without it the app builds and runs, reads may appear to work, and every write
fails with *Not authorized*. This package's own example had exactly that
mistake, and it cost several releases of a README claiming writes were
unverified.

## Android setup

Health Connect requires **minSdk 26**, and the permissions your app uses must
be declared in `AndroidManifest.xml`. Health Connect is built in from Android
14; older devices need it installed from the Play Store, which
`isAvailable()` reports.

Two types are unsupported here and say so rather than returning something
close: **`mindfulSession`**, which Health Connect does not model, and
**`basalEnergyBurned`**, whose nearest record is a rate rather than an interval
total.

## License

MIT © K M Shahriar Hossain
