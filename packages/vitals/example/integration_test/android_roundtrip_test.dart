import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitals/vitals.dart';

/// Exercises Health Connect against real stored data.
///
/// Unlike iOS, Android's health permissions are ordinary Android permissions,
/// so a test can be pre-authorised:
///
///   adb shell pm grant com.devshakib.vitals_example \
///     android.permission.health.WRITE_HYDRATION
///
/// That makes the full write-read-aggregate-delete cycle verifiable here in a
/// way it is not on iOS, where no equivalent exists.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Vitals vitals = Vitals.instance;
  final DateTime now = DateTime.now();
  final DateTime from = now.subtract(const Duration(hours: 2));
  final DateTime to = now.add(const Duration(hours: 2));

  setUpAll(() async {
    // Leave no residue from an earlier run.
    await vitals.delete(VitalType.water, from: from, to: to);
    await vitals.delete(VitalType.bodyMass, from: from, to: to);
    await vitals.delete(VitalType.steps, from: from, to: to);
  });

  testWidgets('Health Connect is available on this device', (_) async {
    expect(await vitals.isAvailable(), isTrue);
  });

  testWidgets('read access is answerable here, unlike iOS', (_) async {
    final Map<VitalType<VitalSample>, bool>? access =
        await vitals.readAccessOnAndroid(<VitalType<VitalSample>>{
      VitalType.steps,
      VitalType.water,
    });
    expect(
      access,
      isNotNull,
      reason: 'Health Connect can report read access; HealthKit cannot',
    );
    expect(access![VitalType.steps], isTrue);
    expect(access[VitalType.water], isTrue);
  });

  testWidgets('write access is reported per type', (_) async {
    final Map<VitalType<VitalSample>, WriteAccess> access =
        await vitals.writeAccess(<VitalType<VitalSample>>{VitalType.water});
    expect(access[VitalType.water], WriteAccess.granted);
  });

  testWidgets('a volume round-trips through the store', (_) async {
    await vitals.writeVolume(
      VitalType.water,
      const Volume.millilitres(250),
      at: now,
    );

    final List<VolumeSample> back = await vitals.read(
      VitalType.water,
      from: from,
      to: to,
    );

    expect(back, hasLength(1));
    expect(back.single.value.millilitres, closeTo(250, 0.001));
    expect(back.single.source.name, isNotEmpty);
  });

  testWidgets('a mass round-trips with its unit intact', (_) async {
    // Written in pounds, stored in kilograms, read back as a Mass. If any of
    // the three conversion sites disagreed, this is where it would show.
    await vitals.writeMass(VitalType.bodyMass, const Mass.pounds(180), at: now);

    final List<MassSample> back = await vitals.read(
      VitalType.bodyMass,
      from: from,
      to: to,
    );

    expect(back, hasLength(1));
    expect(back.single.value.kilograms, closeTo(81.6466, 0.01));
    expect(back.single.value.pounds, closeTo(180, 0.01));
  });

  testWidgets('counts round-trip and aggregate', (_) async {
    final DateTime base = DateTime(now.year, now.month, now.day, now.hour);
    for (final int steps in <int>[1000, 2500]) {
      await vitals.writeCount(
        VitalType.steps,
        steps,
        from: base,
        to: base.add(const Duration(minutes: 10)),
      );
    }

    final List<CountSample> samples = await vitals.read(
      VitalType.steps,
      from: base.subtract(const Duration(minutes: 1)),
      to: base.add(const Duration(hours: 1)),
    );
    expect(
      samples.map((CountSample s) => s.count),
      containsAll(<int>[1000, 2500]),
    );

    final List<VitalStatistic> hourly = await vitals.statistics(
      VitalType.steps,
      from: base,
      to: base.add(const Duration(hours: 1)),
      bucket: VitalBucket.hourly,
    );
    expect(hourly, hasLength(1));
    expect(
      hourly.single.value,
      3500.0,
      reason: 'steps sum, and the reduction happens on the platform',
    );
  });

  testWidgets('an empty bucket reports null, not zero', (_) async {
    final DateTime quiet = now.subtract(const Duration(days: 300));
    final List<VitalStatistic> stats = await vitals.statistics(
      VitalType.steps,
      from: quiet,
      to: quiet.add(const Duration(days: 2)),
      bucket: VitalBucket.daily,
    );
    expect(stats, hasLength(2));
    expect(
      stats.every((VitalStatistic s) => s.value == null),
      isTrue,
      reason: 'no data and a recorded zero must stay distinguishable',
    );
  });

  testWidgets('types Health Connect cannot model say so', (_) async {
    for (final VitalType<VitalSample> type in <VitalType<VitalSample>>[
      VitalType.mindfulSession,
      VitalType.basalEnergyBurned,
    ]) {
      await expectLater(
        vitals.read(type, from: from, to: to),
        throwsA(isA<UnsupportedVitalTypeException>()),
        reason: '${type.id} is reported, not approximated',
      );
    }
  });

  testWidgets('delete removes what was written and reports the count', (
    _,
  ) async {
    final int removed = await vitals.delete(
      VitalType.water,
      from: from,
      to: to,
    );
    expect(removed, greaterThanOrEqualTo(1));
    expect(await vitals.read(VitalType.water, from: from, to: to), isEmpty);
  });

  tearDownAll(() async {
    await vitals.delete(VitalType.bodyMass, from: from, to: to);
    await vitals.delete(VitalType.steps, from: from, to: to);
  });
}
