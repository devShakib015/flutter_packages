import 'method_channel_vitals.dart';
import 'permissions.dart';
import 'statistics.dart';
import 'units.dart';
import 'vital_sample.dart';
import 'vital_type.dart';

/// Read and write health data.
///
/// Implemented by the platform-backed instance and by `FakeVitals`, so an app
/// can be tested without a device that has health data on it.
///
/// ```dart
/// final vitals = Vitals.instance;
/// await vitals.requestPermissions(
///   const PermissionRequest(read: {VitalType.steps, VitalType.heartRate}),
/// );
///
/// final daily = await vitals.statistics(
///   VitalType.steps,
///   from: DateTime.now().subtract(const Duration(days: 30)),
///   to: DateTime.now(),
///   bucket: VitalBucket.daily,
/// );
/// ```
abstract interface class Vitals {
  /// The platform-backed instance.
  ///
  /// Swap in a `FakeVitals` in tests rather than reaching for this.
  static const Vitals instance = MethodChannelVitals();

  /// Whether health data is usable on this device at all.
  ///
  /// False on iOS simulators without HealthKit, on Android without Health
  /// Connect installed, and on every other platform.
  Future<bool> isAvailable();

  /// Asks the user for access.
  ///
  /// Returns whether the sheet was shown and completed — **not** whether
  /// anything was granted. On iOS that distinction is unavoidable; see
  /// [VitalsReadProbe].
  Future<bool> requestPermissions(PermissionRequest request);

  /// Write access per type, which both platforms can report truthfully.
  Future<Map<VitalType<VitalSample>, WriteAccess>> writeAccess(
    Set<VitalType<VitalSample>> types,
  );

  /// Read access per type, on Android only.
  ///
  /// Returns null on iOS, where the platform genuinely cannot answer. That
  /// asymmetry is deliberate: a package that returned a confident answer on
  /// both would be lying on one of them.
  Future<Map<VitalType<VitalSample>, bool>?> readAccessOnAndroid(
    Set<VitalType<VitalSample>> types,
  );

  /// Reads raw samples.
  ///
  /// Prefer [statistics] for anything summarised — a year of heart-rate
  /// samples is hundreds of thousands of points, and moving them across the
  /// platform channel to sum them in Dart is far slower than letting the
  /// platform reduce them.
  Future<List<T>> read<T extends VitalSample>(
    VitalType<T> type, {
    required DateTime from,
    required DateTime to,
    int? limit,
  });

  /// Reduces samples into buckets, on the platform side.
  ///
  /// Uses [VitalType.defaultAggregate] unless [aggregate] says otherwise, so
  /// steps sum and heart rates average without being told.
  Future<List<VitalStatistic>> statistics(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
    required VitalBucket bucket,
    VitalAggregate? aggregate,
  });

  /// Whether any sample of [type] exists in the range.
  ///
  /// The honest substitute for a read-permission check on iOS: a false result
  /// means either no data or no permission, and nothing can tell you which.
  Future<bool> hasAnyData(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  });

  /// Writes a whole-number tally.
  Future<void> writeCount(
    VitalType<CountSample> type,
    int count, {
    required DateTime from,
    required DateTime to,
  });

  /// Writes a mass, such as body weight.
  Future<void> writeMass(
    VitalType<MassSample> type,
    Mass value, {
    required DateTime at,
  });

  /// Writes a length, such as height or distance.
  Future<void> writeLength(
    VitalType<LengthSample> type,
    Length value, {
    required DateTime from,
    required DateTime to,
  });

  /// Writes an energy amount.
  Future<void> writeEnergy(
    VitalType<EnergySample> type,
    Energy value, {
    required DateTime from,
    required DateTime to,
  });

  /// Writes a per-minute rate, such as heart rate.
  Future<void> writeRate(
    VitalType<RateSample> type,
    double perMinute, {
    required DateTime at,
  });

  /// Writes a proportion, given as a fraction from 0 to 1.
  Future<void> writePercent(
    VitalType<PercentSample> type,
    double fraction, {
    required DateTime at,
  });

  /// Writes a volume, such as water drunk.
  Future<void> writeVolume(
    VitalType<VolumeSample> type,
    Volume value, {
    required DateTime at,
  });

  /// Removes samples this app wrote.
  ///
  /// Neither platform lets an app delete data another app recorded, so this
  /// only affects your own writes. Returns how many were removed.
  Future<int> delete(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  });
}
