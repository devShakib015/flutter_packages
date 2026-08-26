import 'dart:math' as math;

import 'permissions.dart';
import 'statistics.dart';
import 'units.dart';
import 'vital_sample.dart';
import 'vital_type.dart';
import 'vitals.dart';

/// An in-memory [Vitals] for tests and previews.
///
/// Health flows are otherwise untestable: they need a real device, with real
/// data, and a permission sheet a test cannot tap. Point your app at this and
/// the whole flow runs in CI.
///
/// ```dart
/// final fake = FakeVitals()
///   ..seedCounts(VitalType.steps, <DateTime, int>{
///     DateTime(2026, 8, 24): 8210,
///     DateTime(2026, 8, 25): 11430,
///   });
///
/// expect(await fake.statistics(VitalType.steps, ...), hasLength(2));
/// ```
///
/// It also models the awkward parts rather than assuming the happy path:
/// [available], [permissionSheetSucceeds] and [readsAreBlocked] let a test
/// exercise an ineligible device, a refused sheet, and the iOS case where
/// reads return empty because permission was silently denied.
class FakeVitals implements Vitals {
  /// Creates an empty fake.
  FakeVitals({
    this.available = true,
    this.permissionSheetSucceeds = true,
    this.readsAreBlocked = false,
  });

  /// Whether [isAvailable] reports the platform as usable.
  bool available;

  /// Whether [requestPermissions] reports the sheet completed.
  bool permissionSheetSucceeds;

  /// Whether reads return empty regardless of stored data.
  ///
  /// Reproduces the iOS case that cannot be detected: the user refused read
  /// access, so queries succeed and return nothing.
  bool readsAreBlocked;

  final Map<String, List<VitalSample>> _store = <String, List<VitalSample>>{};
  final Map<String, WriteAccess> _writeAccess = <String, WriteAccess>{};
  final Map<String, bool> _readAccess = <String, bool>{};

  /// Every request made, in order. Useful for asserting call sites.
  final List<PermissionRequest> requestedPermissions = <PermissionRequest>[];

  /// Whether this fake pretends to be Android for [readAccessOnAndroid].
  bool pretendAndroid = false;

  // ------------------------------------------------------------- seeding

  /// Stores [samples] for [type].
  void seed<T extends VitalSample>(VitalType<T> type, List<T> samples) {
    _store.putIfAbsent(type.id, () => <VitalSample>[]).addAll(samples);
    _store[type.id]!.sort(
      (VitalSample a, VitalSample b) => a.start.compareTo(b.start),
    );
  }

  /// Convenience for whole-day tallies such as steps.
  void seedCounts(VitalType<CountSample> type, Map<DateTime, int> byDay) {
    seed<CountSample>(type, <CountSample>[
      for (final MapEntry<DateTime, int> e in byDay.entries)
        CountSample(
          count: e.value,
          start: e.key,
          end: e.key.add(const Duration(days: 1)),
          source: const VitalSource(name: 'FakeVitals'),
        ),
    ]);
  }

  /// Sets what [writeAccess] reports for [type].
  void setWriteAccess(VitalType<VitalSample> type, WriteAccess access) =>
      _writeAccess[type.id] = access;

  /// Sets what [readAccessOnAndroid] reports for [type].
  void setReadAccess(VitalType<VitalSample> type, {required bool granted}) =>
      _readAccess[type.id] = granted;

  /// Empties the store.
  void reset() {
    _store.clear();
    _writeAccess.clear();
    _readAccess.clear();
    requestedPermissions.clear();
  }

  // --------------------------------------------------------------- reads

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestPermissions(PermissionRequest request) async {
    requestedPermissions.add(request);
    if (permissionSheetSucceeds) {
      for (final VitalType<VitalSample> type in request.write) {
        _writeAccess.putIfAbsent(type.id, () => WriteAccess.granted);
      }
      for (final VitalType<VitalSample> type in request.read) {
        _readAccess.putIfAbsent(type.id, () => !readsAreBlocked);
      }
    }
    return permissionSheetSucceeds;
  }

  @override
  Future<Map<VitalType<VitalSample>, WriteAccess>> writeAccess(
    Set<VitalType<VitalSample>> types,
  ) async => <VitalType<VitalSample>, WriteAccess>{
    for (final VitalType<VitalSample> t in types)
      t: _writeAccess[t.id] ?? WriteAccess.notDetermined,
  };

  @override
  Future<Map<VitalType<VitalSample>, bool>?> readAccessOnAndroid(
    Set<VitalType<VitalSample>> types,
  ) async {
    if (!pretendAndroid) return null;
    return <VitalType<VitalSample>, bool>{
      for (final VitalType<VitalSample> t in types)
        t: _readAccess[t.id] ?? false,
    };
  }

  @override
  Future<List<T>> read<T extends VitalSample>(
    VitalType<T> type, {
    required DateTime from,
    required DateTime to,
    int? limit,
  }) async {
    if (readsAreBlocked) return <T>[];
    final List<T> matches = <T>[
      for (final VitalSample s in _store[type.id] ?? const <VitalSample>[])
        if (!s.start.isBefore(from) && s.start.isBefore(to)) s as T,
    ];
    if (limit != null && matches.length > limit) {
      return matches.sublist(matches.length - limit);
    }
    return matches;
  }

  @override
  Future<bool> hasAnyData(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  }) async => (await read(type, from: from, to: to, limit: 1)).isNotEmpty;

  @override
  Future<List<VitalStatistic>> statistics(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
    required VitalBucket bucket,
    VitalAggregate? aggregate,
  }) async {
    final VitalAggregate how = aggregate ?? type.defaultAggregate;
    final List<VitalSample> samples = await read(type, from: from, to: to);

    final List<VitalStatistic> out = <VitalStatistic>[];
    DateTime cursor = _floor(from, bucket);
    while (cursor.isBefore(to)) {
      final DateTime next = _advance(cursor, bucket);
      final List<double> values = <double>[
        for (final VitalSample s in samples)
          if (!s.start.isBefore(cursor) && s.start.isBefore(next))
            if (s.aggregableValue case final double v) v,
      ];
      out.add(
        VitalStatistic(
          start: cursor,
          end: next,
          value: values.isEmpty ? null : _reduce(values, how),
          aggregate: how,
        ),
      );
      cursor = next;
    }
    return out;
  }

  static double _reduce(List<double> values, VitalAggregate how) =>
      switch (how) {
        VitalAggregate.sum => values.reduce((double a, double b) => a + b),
        VitalAggregate.average =>
          values.reduce((double a, double b) => a + b) / values.length,
        VitalAggregate.minimum => values.reduce(math.min),
        VitalAggregate.maximum => values.reduce(math.max),
        VitalAggregate.latest => values.last,
      };

  /// Snaps to the start of the bucket containing [t], in local time.
  static DateTime _floor(DateTime t, VitalBucket bucket) => switch (bucket) {
    VitalBucket.hourly => DateTime(t.year, t.month, t.day, t.hour),
    VitalBucket.daily => DateTime(t.year, t.month, t.day),
    VitalBucket.weekly => DateTime(
      t.year,
      t.month,
      t.day,
    ).subtract(Duration(days: t.weekday - DateTime.monday)),
    VitalBucket.monthly => DateTime(t.year, t.month),
  };

  /// Steps one bucket forward, honouring month lengths and DST.
  static DateTime _advance(DateTime t, VitalBucket bucket) => switch (bucket) {
    VitalBucket.hourly => DateTime(t.year, t.month, t.day, t.hour + 1),
    VitalBucket.daily => DateTime(t.year, t.month, t.day + 1),
    VitalBucket.weekly => DateTime(t.year, t.month, t.day + 7),
    VitalBucket.monthly => DateTime(t.year, t.month + 1),
  };

  // -------------------------------------------------------------- writes

  void _record(VitalType<VitalSample> type, VitalSample sample) {
    if (_writeAccess[type.id] == WriteAccess.denied) {
      throw StateError('Write access to ${type.id} was denied.');
    }
    _store.putIfAbsent(type.id, () => <VitalSample>[]).add(sample);
    _store[type.id]!.sort(
      (VitalSample a, VitalSample b) => a.start.compareTo(b.start),
    );
  }

  static const VitalSource _self = VitalSource(name: 'FakeVitals');

  @override
  Future<void> writeCount(
    VitalType<CountSample> type,
    int count, {
    required DateTime from,
    required DateTime to,
  }) async => _record(
    type,
    CountSample(count: count, start: from, end: to, source: _self),
  );

  @override
  Future<void> writeMass(
    VitalType<MassSample> type,
    Mass value, {
    required DateTime at,
  }) async => _record(
    type,
    MassSample(value: value, start: at, end: at, source: _self),
  );

  @override
  Future<void> writeLength(
    VitalType<LengthSample> type,
    Length value, {
    required DateTime from,
    required DateTime to,
  }) async => _record(
    type,
    LengthSample(value: value, start: from, end: to, source: _self),
  );

  @override
  Future<void> writeEnergy(
    VitalType<EnergySample> type,
    Energy value, {
    required DateTime from,
    required DateTime to,
  }) async => _record(
    type,
    EnergySample(value: value, start: from, end: to, source: _self),
  );

  @override
  Future<void> writeRate(
    VitalType<RateSample> type,
    double perMinute, {
    required DateTime at,
  }) async => _record(
    type,
    RateSample(perMinute: perMinute, start: at, end: at, source: _self),
  );

  @override
  Future<void> writePercent(
    VitalType<PercentSample> type,
    double fraction, {
    required DateTime at,
  }) async => _record(
    type,
    PercentSample(fraction: fraction, start: at, end: at, source: _self),
  );

  @override
  Future<void> writeVolume(
    VitalType<VolumeSample> type,
    Volume value, {
    required DateTime at,
  }) async => _record(
    type,
    VolumeSample(value: value, start: at, end: at, source: _self),
  );

  @override
  Future<int> delete(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  }) async {
    final List<VitalSample>? list = _store[type.id];
    if (list == null) return 0;
    final int before = list.length;
    list.removeWhere(
      (VitalSample s) =>
          !s.start.isBefore(from) &&
          s.start.isBefore(to) &&
          s.source.name == _self.name,
    );
    return before - list.length;
  }
}
