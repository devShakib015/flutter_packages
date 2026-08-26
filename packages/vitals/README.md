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

> **Status.** iOS is complete and verified against a real HealthKit store.
> Android reads and aggregates but does not yet write or delete. Two types have
> no Health Connect equivalent and say so rather than approximating.

## Why another one

`health` is the established package, it is actively maintained, and it covers
more data types than this does. If you need breadth today, use it. This exists
for three things it does not do.

**Nothing is cast.** The type you ask for decides the type you get back:

```dart
final weight = await vitals.read(VitalType.bodyMass, from: a, to: b);
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
switch (await vitals.readAccessOnAndroid({VitalType.steps})) {
  case null:            // iOS: unknowable, attempt the read and handle empty
  case final access:    // Android: an actual answer
}
```

## Statistics, not raw samples

A year of heart-rate readings is hundreds of thousands of points. Reducing them
on the platform beats shipping them across the channel:

```dart
final daily = await vitals.statistics(
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
