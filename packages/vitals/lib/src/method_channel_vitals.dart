import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'permissions.dart';
import 'statistics.dart';
import 'units.dart';
import 'vital_sample.dart';
import 'vital_type.dart';
import 'vitals.dart';

/// Talks to HealthKit and Health Connect over a method channel.
///
/// Reached through `Vitals.instance`; there is no reason to construct it
/// directly. Every method degrades to an unavailable answer on platforms
/// without an implementation rather than throwing, so a cross-platform app
/// does not need to branch on `Platform.isIOS` before calling.
class MethodChannelVitals implements Vitals {
  /// Creates the platform-backed implementation.
  const MethodChannelVitals();

  static const MethodChannel _channel = MethodChannel('dev.shakib/vitals');

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Web, desktop, or a build without the plugin.
      return null;
    } on PlatformException catch (e) {
      throw _translate(e);
    }
  }

  /// Turns a platform error into something a caller can branch on.
  static VitalsException _translate(PlatformException e) {
    final String text = e.message ?? e.code;
    // HealthKit uses one message for a family of situations, and the only one
    // worth distinguishing is querying before ever asking.
    if (e.code == 'authorizationNotDetermined' ||
        text.toLowerCase().contains('authorization') &&
            text.toLowerCase().contains('not determined')) {
      return AuthorizationNotDeterminedException(
        'Call requestPermissions() before reading. $text',
      );
    }
    return switch (e.code) {
      'unavailable' => HealthDataUnavailableException(text),
      'unsupportedOnAndroid' ||
      'unknownType' ||
      'unwritable' ||
      'unsupportedAggregate' =>
        UnsupportedVitalTypeException(
          e.details?.toString() ?? '?',
          text,
        ),
      'write' => VitalsWriteException(text),
      _ => VitalsPlatformException(text, code: e.code),
    };
  }

  static int _ms(DateTime t) => t.toUtc().millisecondsSinceEpoch;

  Map<String, Object?> _range(DateTime from, DateTime to) => <String, Object?>{
        'from': _ms(from),
        'to': _ms(to),
      };

  @override
  Future<bool> isAvailable() async =>
      await _invoke<bool>('isAvailable') ?? false;

  @override
  Future<bool> requestPermissions(PermissionRequest request) async {
    if (request.isEmpty) return true;
    return await _invoke<bool>('requestPermissions', request.toJson()) ?? false;
  }

  @override
  Future<Map<VitalType<VitalSample>, WriteAccess>> writeAccess(
    Set<VitalType<VitalSample>> types,
  ) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'writeAccess',
      <String, Object?>{
        'types': types.map((VitalType<VitalSample> t) => t.id).toList(),
      },
    );
    return <VitalType<VitalSample>, WriteAccess>{
      for (final VitalType<VitalSample> type in types)
        type: _writeAccessFrom(raw?[type.id] as String?),
    };
  }

  static WriteAccess _writeAccessFrom(String? raw) => switch (raw) {
        'granted' => WriteAccess.granted,
        'denied' => WriteAccess.denied,
        _ => WriteAccess.notDetermined,
      };

  @override
  Future<Map<VitalType<VitalSample>, bool>?> readAccessOnAndroid(
    Set<VitalType<VitalSample>> types,
  ) async {
    final Map<Object?, Object?>? raw = await _invoke<Map<Object?, Object?>>(
      'readAccess',
      <String, Object?>{
        'types': types.map((VitalType<VitalSample> t) => t.id).toList(),
      },
    );
    // iOS answers null on purpose: the platform cannot report read access.
    if (raw == null) return null;
    return <VitalType<VitalSample>, bool>{
      for (final VitalType<VitalSample> type in types)
        type: raw[type.id] == true,
    };
  }

  @override
  Future<List<T>> read<T extends VitalSample>(
    VitalType<T> type, {
    required DateTime from,
    required DateTime to,
    int? limit,
  }) async {
    final List<Object?>? raw = await _invoke<List<Object?>>(
      'read',
      <String, Object?>{
        'type': type.id,
        ..._range(from, to),
        if (limit != null) 'limit': limit,
      },
    );
    if (raw == null) return <T>[];
    return <T>[
      for (final Object? entry in raw)
        type.decode((entry as Map<Object?, Object?>?) ?? const {}),
    ];
  }

  @override
  Future<bool> hasAnyData(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  }) async =>
      (await read(type, from: from, to: to, limit: 1)).isNotEmpty;

  @override
  Future<List<VitalStatistic>> statistics(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
    required VitalBucket bucket,
    VitalAggregate? aggregate,
  }) async {
    final VitalAggregate how = aggregate ?? type.defaultAggregate;
    final List<Object?>? raw = await _invoke<List<Object?>>(
      'statistics',
      <String, Object?>{
        'type': type.id,
        ..._range(from, to),
        'bucket': bucket.wireName,
        'aggregate': how.name,
      },
    );
    if (raw == null) return <VitalStatistic>[];
    return <VitalStatistic>[
      for (final Object? entry in raw)
        VitalStatistic.fromMap(
          (entry as Map<Object?, Object?>?) ?? const {},
          how,
        ),
    ];
  }

  Future<void> _write(
    VitalType<VitalSample> type,
    double value,
    DateTime from,
    DateTime to,
  ) async {
    await _invoke<void>('write', <String, Object?>{
      'type': type.id,
      'value': value,
      ..._range(from, to),
    });
  }

  @override
  Future<void> writeCount(
    VitalType<CountSample> type,
    int count, {
    required DateTime from,
    required DateTime to,
  }) =>
      _write(type, count.toDouble(), from, to);

  @override
  Future<void> writeMass(
    VitalType<MassSample> type,
    Mass value, {
    required DateTime at,
  }) =>
      _write(type, value.kilograms, at, at);

  @override
  Future<void> writeLength(
    VitalType<LengthSample> type,
    Length value, {
    required DateTime from,
    required DateTime to,
  }) =>
      _write(type, value.metres, from, to);

  @override
  Future<void> writeEnergy(
    VitalType<EnergySample> type,
    Energy value, {
    required DateTime from,
    required DateTime to,
  }) =>
      _write(type, value.kilocalories, from, to);

  @override
  Future<void> writeRate(
    VitalType<RateSample> type,
    double perMinute, {
    required DateTime at,
  }) =>
      _write(type, perMinute, at, at);

  @override
  Future<void> writePercent(
    VitalType<PercentSample> type,
    double fraction, {
    required DateTime at,
  }) =>
      _write(type, fraction, at, at);

  @override
  Future<void> writeVolume(
    VitalType<VolumeSample> type,
    Volume value, {
    required DateTime at,
  }) =>
      _write(type, value.litres, at, at);

  @override
  Future<int> delete(
    VitalType<VitalSample> type, {
    required DateTime from,
    required DateTime to,
  }) async =>
      await _invoke<int>('delete', <String, Object?>{
        'type': type.id,
        ..._range(from, to),
      }) ??
      0;
}
