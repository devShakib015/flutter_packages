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

export 'src/fake_vitals.dart';
export 'src/method_channel_vitals.dart';
export 'src/permissions.dart';
export 'src/statistics.dart';
export 'src/units.dart';
export 'src/vital_sample.dart';
export 'src/vital_type.dart';
export 'src/vitals.dart';
