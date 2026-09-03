import 'package:flutter/foundation.dart';

import 'vital_type.dart';

/// How wide each statistics bucket is.
enum VitalBucket {
  /// One bucket per hour.
  hourly,

  /// One bucket per calendar day, in the device's local time zone.
  daily,

  /// One bucket per week.
  weekly,

  /// One bucket per calendar month.
  monthly;

  /// Wire representation.
  String get wireName => name;
}

/// One reduced value covering a span of time.
@immutable
class VitalStatistic {
  /// Creates a statistic.
  const VitalStatistic({
    required this.start,
    required this.end,
    required this.value,
    required this.aggregate,
  });

  /// Start of the bucket.
  final DateTime start;

  /// End of the bucket, exclusive.
  final DateTime end;

  /// The reduced value, or null when the bucket held no samples.
  ///
  /// Null and zero mean different things: no data recorded versus a recorded
  /// zero. Collapsing them is a common source of wrong averages.
  final double? value;

  /// How the samples were reduced.
  final VitalAggregate aggregate;

  /// Whether any samples fell in this bucket.
  bool get hasData => value != null;

  /// Reads one off the platform channel.
  factory VitalStatistic.fromMap(
    Map<Object?, Object?> map,
    VitalAggregate aggregate,
  ) {
    DateTime at(Object? v) => DateTime.fromMillisecondsSinceEpoch(
          (v as num?)?.toInt() ?? 0,
          isUtc: true,
        ).toLocal();
    return VitalStatistic(
      start: at(map['start']),
      end: at(map['end']),
      value: (map['value'] as num?)?.toDouble(),
      aggregate: aggregate,
    );
  }

  @override
  String toString() =>
      'VitalStatistic(${start.toIso8601String().split("T").first}: $value)';
}
