/// Type-safe access to Apple Health and Health Connect.
///
/// ```dart
/// final vitals = Vitals.instance;
/// await vitals.requestPermissions(
///   const PermissionRequest(read: {VitalType.steps}),
/// );
///
/// final daily = await vitals.statistics(
///   VitalType.steps,
///   from: DateTime.now().subtract(const Duration(days: 30)),
///   to: DateTime.now(),
///   bucket: VitalBucket.daily,
/// );
/// ```
library;

export 'src/exceptions.dart'
    show
        AuthorizationNotDeterminedException,
        HealthDataUnavailableException,
        UnsupportedVitalTypeException,
        VitalsException,
        VitalsPlatformException,
        VitalsWriteException;
export 'src/fake_vitals.dart' show FakeVitals;
export 'src/method_channel_vitals.dart' show MethodChannelVitals;
export 'src/permissions.dart'
    show PermissionRequest, VitalsReadProbe, WriteAccess;
export 'src/statistics.dart' show VitalBucket, VitalStatistic;
export 'src/units.dart'
    show Concentration, Energy, Length, Mass, Pressure, Temperature, Volume;
export 'src/vital_sample.dart'
    show
        ConcentrationSample,
        CountSample,
        DurationSample,
        EnergySample,
        LengthSample,
        MassSample,
        PercentSample,
        PressureSample,
        RateSample,
        SleepSample,
        SleepStage,
        TemperatureSample,
        VitalSample,
        VitalSource,
        VolumeSample,
        WorkoutSample;
export 'src/vital_type.dart' show VitalAggregate, VitalType;
export 'src/vitals.dart';
