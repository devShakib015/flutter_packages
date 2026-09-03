import 'package:flutter_test/flutter_test.dart';
import 'package:vitals/vitals.dart';

void main() {
  group('units', () {
    test('convert without drifting', () {
      expect(const Mass.pounds(154).kilograms, closeTo(69.85, 0.01));
      expect(const Mass.kilograms(70).pounds, closeTo(154.32, 0.01));
      expect(const Length.miles(1).metres, closeTo(1609.344, 0.001));
      expect(const Length.feet(6).centimetres, closeTo(182.88, 0.01));
      expect(const Energy.kilojoules(100).kilocalories, closeTo(23.9, 0.1));
      expect(const Temperature.fahrenheit(98.6).celsius, closeTo(37, 0.01));
      expect(const Volume.fluidOuncesUS(8).millilitres, closeTo(236.6, 0.1));
      expect(
        const Concentration.milligramsPerDecilitre(100).millimolesPerLitre,
        closeTo(5.55, 0.01),
      );
    });

    test('round-trip through the non-canonical unit', () {
      expect(
        Mass.pounds(const Mass.kilograms(81.5).pounds).kilograms,
        closeTo(81.5, 1e-9),
      );
      expect(
        Temperature.fahrenheit(const Temperature.celsius(21).fahrenheit)
            .celsius,
        closeTo(21, 1e-9),
      );
    });

    test('compare and equate by canonical value', () {
      expect(const Mass.kilograms(1), const Mass.grams(1000));
      expect(const Mass.kilograms(2).compareTo(const Mass.kilograms(3)), -1);
    });
  });

  group('type registry', () {
    test('ids are unique and resolvable', () {
      final Set<String> ids =
          VitalType.all.map((VitalType<VitalSample> t) => t.id).toSet();
      expect(ids, hasLength(VitalType.all.length), reason: 'duplicate id');
      for (final VitalType<VitalSample> type in VitalType.all) {
        expect(VitalType.byId(type.id), same(type));
      }
      expect(VitalType.byId('not-a-type'), isNull);
    });

    test('default aggregates suit the measurement', () {
      // Summing heart rates is nonsense; summing steps is the whole point.
      expect(VitalType.steps.defaultAggregate, VitalAggregate.sum);
      expect(
        VitalType.distanceWalkingRunning.defaultAggregate,
        VitalAggregate.sum,
      );
      expect(VitalType.heartRate.defaultAggregate, VitalAggregate.average);
      expect(
        VitalType.oxygenSaturation.defaultAggregate,
        VitalAggregate.average,
      );
      // A standing measurement should report the newest, not a total.
      expect(VitalType.bodyMass.defaultAggregate, VitalAggregate.latest);
      expect(VitalType.height.defaultAggregate, VitalAggregate.latest);
    });

    test('workouts are marked unwritable', () {
      expect(VitalType.workout.writable, isFalse);
      expect(VitalType.steps.writable, isTrue);
    });
  });

  group('type safety', () {
    late FakeVitals vitals;
    final DateTime day = DateTime(2026, 8, 20);

    setUp(() {
      vitals = FakeVitals()
        ..seedCounts(VitalType.steps, <DateTime, int>{day: 8000})
        ..seed<MassSample>(VitalType.bodyMass, <MassSample>[
          MassSample(
            value: const Mass.kilograms(72.5),
            start: day,
            end: day,
            source: const VitalSource(name: 'test'),
          ),
        ]);
    });

    test('reads come back as the concrete type, no casting', () async {
      final List<CountSample> steps = await vitals.read(
        VitalType.steps,
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      // The point: `.count` is an int, reached without a cast.
      expect(steps.single.count, 8000);

      final List<MassSample> weight = await vitals.read(
        VitalType.bodyMass,
        from: day,
        to: day.add(const Duration(days: 1)),
      );
      expect(weight.single.value.pounds, closeTo(159.8, 0.1));
    });

    test('every sample reports an aggregable value', () {
      const VitalSource src = VitalSource(name: 'x');
      final DateTime t = DateTime(2026);
      expect(
        CountSample(count: 5, start: t, end: t, source: src).aggregableValue,
        5.0,
      );
      expect(
        MassSample(
          value: const Mass.kilograms(9),
          start: t,
          end: t,
          source: src,
        ).aggregableValue,
        9.0,
      );
      expect(
        SleepSample(
          stage: SleepStage.deep,
          start: t,
          end: t.add(const Duration(minutes: 90)),
          source: src,
        ).aggregableValue,
        90.0,
        reason: 'interval samples report elapsed minutes',
      );
    });

    test('sleep stages know whether they count as asleep', () {
      expect(SleepStage.deep.isAsleep, isTrue);
      expect(SleepStage.rem.isAsleep, isTrue);
      expect(SleepStage.awake.isAsleep, isFalse);
      expect(SleepStage.inBed.isAsleep, isFalse);
    });
  });

  group('statistics', () {
    late FakeVitals vitals;

    setUp(() {
      vitals = FakeVitals()
        ..seedCounts(VitalType.steps, <DateTime, int>{
          DateTime(2026, 8, 20): 8000,
          DateTime(2026, 8, 21): 12000,
          // 22nd deliberately missing.
          DateTime(2026, 8, 23): 5000,
        });
    });

    test('buckets daily and sums', () async {
      final List<VitalStatistic> stats = await vitals.statistics(
        VitalType.steps,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 24),
        bucket: VitalBucket.daily,
      );
      expect(stats, hasLength(4));
      expect(stats.map((VitalStatistic s) => s.value).toList(), <double?>[
        8000,
        12000,
        null,
        5000,
      ]);
    });

    test('an empty bucket is null, not zero', () async {
      final List<VitalStatistic> stats = await vitals.statistics(
        VitalType.steps,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 24),
        bucket: VitalBucket.daily,
      );
      final VitalStatistic missing = stats[2];
      expect(missing.value, isNull);
      expect(
        missing.hasData,
        isFalse,
        reason: 'no data recorded and a recorded zero are different things',
      );
    });

    test(
      'averages instead of summing where that is the sensible default',
      () async {
        final DateTime t = DateTime(2026, 8, 20, 9);
        vitals.seed<RateSample>(VitalType.heartRate, <RateSample>[
          for (final double bpm in <double>[60, 80, 100])
            RateSample(
              perMinute: bpm,
              start: t,
              end: t,
              source: const VitalSource(name: 'test'),
            ),
        ]);
        final List<VitalStatistic> stats = await vitals.statistics(
          VitalType.heartRate,
          from: DateTime(2026, 8, 20),
          to: DateTime(2026, 8, 21),
          bucket: VitalBucket.daily,
        );
        expect(stats.single.value, 80.0);
        expect(stats.single.aggregate, VitalAggregate.average);
      },
    );

    test('an explicit aggregate overrides the default', () async {
      final List<VitalStatistic> stats = await vitals.statistics(
        VitalType.steps,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 24),
        bucket: VitalBucket.weekly,
        aggregate: VitalAggregate.maximum,
      );
      expect(stats.single.value, 12000);
    });

    test('monthly buckets respect month lengths', () async {
      final List<VitalStatistic> stats = await vitals.statistics(
        VitalType.steps,
        from: DateTime(2026, 1, 15),
        to: DateTime(2026, 4, 5),
        bucket: VitalBucket.monthly,
      );
      expect(
          stats.map((VitalStatistic s) => s.start).toList(),
          <DateTime>[
            DateTime(2026),
            DateTime(2026, 2),
            DateTime(2026, 3),
            DateTime(2026, 4),
          ],
          reason: 'buckets snap to calendar months, not 30-day blocks');
    });
  });

  group('permissions, modelled honestly', () {
    test(
      'read access is null on iOS because the platform cannot answer',
      () async {
        final FakeVitals vitals = FakeVitals();
        expect(
          await vitals.readAccessOnAndroid(<VitalType<VitalSample>>{
            VitalType.steps,
          }),
          isNull,
          reason: 'HKAuthorizationStatus reports sharing only',
        );
      },
    );

    test('read access is answerable on Android', () async {
      final FakeVitals vitals = FakeVitals()..pretendAndroid = true;
      vitals.setReadAccess(VitalType.steps, granted: true);
      expect(
        await vitals.readAccessOnAndroid(<VitalType<VitalSample>>{
          VitalType.steps,
        }),
        <VitalType<VitalSample>, bool>{VitalType.steps: true},
      );
    });

    test('write access is reported per type', () async {
      final FakeVitals vitals = FakeVitals();
      vitals.setWriteAccess(VitalType.bodyMass, WriteAccess.denied);
      final Map<VitalType<VitalSample>, WriteAccess> access =
          await vitals.writeAccess(<VitalType<VitalSample>>{
        VitalType.bodyMass,
        VitalType.steps,
      });
      expect(access[VitalType.bodyMass], WriteAccess.denied);
      expect(access[VitalType.steps], WriteAccess.notDetermined);
    });

    test('a silent read denial looks exactly like having no data', () async {
      final FakeVitals vitals = FakeVitals(
        readsAreBlocked: true,
      )..seedCounts(VitalType.steps, <DateTime, int>{DateTime(2026, 8, 20): 1});

      final List<CountSample> steps = await vitals.read(
        VitalType.steps,
        from: DateTime(2026, 8, 20),
        to: DateTime(2026, 8, 21),
      );
      expect(
        steps,
        isEmpty,
        reason: 'this is the iOS case no package can detect',
      );
      expect(
        await vitals.hasAnyData(
          VitalType.steps,
          from: DateTime(2026, 8, 20),
          to: DateTime(2026, 8, 21),
        ),
        isFalse,
      );
    });
  });

  group('writes', () {
    late FakeVitals vitals;
    final DateTime now = DateTime(2026, 8, 26, 12);

    setUp(() => vitals = FakeVitals());

    test('typed writes round-trip', () async {
      await vitals.writeMass(
        VitalType.bodyMass,
        const Mass.pounds(180),
        at: now,
      );
      final List<MassSample> back = await vitals.read(
        VitalType.bodyMass,
        from: now.subtract(const Duration(hours: 1)),
        to: now.add(const Duration(hours: 1)),
      );
      expect(back.single.value.kilograms, closeTo(81.65, 0.01));
    });

    test('a denied write throws rather than silently doing nothing', () async {
      vitals.setWriteAccess(VitalType.bodyMass, WriteAccess.denied);
      await expectLater(
        vitals.writeMass(VitalType.bodyMass, const Mass.kilograms(80), at: now),
        throwsStateError,
      );
    });

    test('delete removes only what this app wrote', () async {
      await vitals.writeVolume(
        VitalType.water,
        const Volume.millilitres(250),
        at: now,
      );
      vitals.seed<VolumeSample>(VitalType.water, <VolumeSample>[
        VolumeSample(
          value: const Volume.millilitres(500),
          start: now,
          end: now,
          source: const VitalSource(name: 'Some Other App'),
        ),
      ]);

      final int removed = await vitals.delete(
        VitalType.water,
        from: now.subtract(const Duration(hours: 1)),
        to: now.add(const Duration(hours: 1)),
      );
      expect(
        removed,
        1,
        reason: 'neither platform lets you delete others\' data',
      );

      final List<VolumeSample> left = await vitals.read(
        VitalType.water,
        from: now.subtract(const Duration(hours: 1)),
        to: now.add(const Duration(hours: 1)),
      );
      expect(left.single.source.name, 'Some Other App');
    });
  });

  group('availability', () {
    test('an ineligible device reports unavailable', () async {
      expect(await FakeVitals(available: false).isAvailable(), isFalse);
    });

    test('a refused sheet grants nothing', () async {
      final FakeVitals vitals = FakeVitals(permissionSheetSucceeds: false);
      expect(
        await vitals.requestPermissions(
          const PermissionRequest(
            write: <VitalType<VitalSample>>{VitalType.bodyMass},
          ),
        ),
        isFalse,
      );
      final Map<VitalType<VitalSample>, WriteAccess> access = await vitals
          .writeAccess(<VitalType<VitalSample>>{VitalType.bodyMass});
      expect(access[VitalType.bodyMass], WriteAccess.notDetermined);
      expect(vitals.requestedPermissions, hasLength(1));
    });
  });
}
