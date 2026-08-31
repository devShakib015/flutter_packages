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

> **Status — read this before writing data.**
>
> **Reading is verified.** The iOS path is exercised against a real HealthKit
> store, and the Dart contract has a full unit-test suite behind it.
>
> **Writing is not verified on either platform.** The code is complete and
> compiles, but no write has yet been observed to succeed end to end: on the
> iOS Simulator `save` returns *Not authorized* even after the permission sheet
> is granted, and the Android round trip has not been run. It is unclear
> whether that is a Simulator limitation or a defect here.
>
> So: use `0.1.0` for reading and aggregating. If you write, verify the values
> land correctly in Health or Health Connect before trusting it — a unit-
> conversion mistake would be silent, and health records are awkward to
> correct. Reports from real devices are very welcome.

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

There is one write method per kind of quantity, and **the compiler picks it for
you**. Each `VitalType` is generic over its sample type, so a mismatch does not
compile:

```dart
await Vitals.instance.writeCount(VitalType.steps, 2400, at: DateTime.now());
await Vitals.instance.writeMass(
  VitalType.bodyMass, 71.2, unit: Mass.kilograms, at: DateTime.now(),
);

await Vitals.instance.writeMass(VitalType.steps, 2400, ...);
// error: VitalType<CountSample> can't be assigned to VitalType<MassSample>
```

The mapping is the type parameter, so you can read it off the type you already
have:

| the type you have | the method that takes it |
| --- | --- |
| `VitalType<CountSample>` — steps, flights | `writeCount` |
| `VitalType<MassSample>` — body mass | `writeMass` |
| `VitalType<LengthSample>` — distance, height | `writeLength` |
| `VitalType<EnergySample>` — active, basal | `writeEnergy` |
| `VitalType<RateSample>` — heart, respiratory | `writeRate` |
| `VitalType<PercentSample>` — oxygen saturation | `writePercent` |
| `VitalType<VolumeSample>` — water | `writeVolume` |

Writing needs permission that reading does not — see
[the three permission states](#the-three-permission-states) — and please read
the status note at the top of this file before relying on it.

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
