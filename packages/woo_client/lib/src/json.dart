/// Readers that coerce instead of casting.
///
/// WordPress is not strict about JSON types, and plugins are less strict
/// still: a boolean arrives as `true`, `"yes"`, `"1"`, or `1` depending on who
/// wrote the field, and an id can be `799` or `"799"`. A hard cast turns any
/// of those into an exception that loses the entire response, over one field
/// nobody was reading.
///
/// These take whatever came and give back something usable, so one odd field
/// costs you that field and not the parse.
///
/// Internal to the package.
library;

/// Reads a string, converting whatever else arrived.
String readString(Object? value) => switch (value) {
  final String s => s,
  null => '',
  _ => '$value',
};

/// Reads an integer, or null when there is nothing usable.
int? readIntOrNull(Object? value) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? double.tryParse(s)?.toInt(),
  final bool b => b ? 1 : 0,
  _ => null,
};

/// Reads an integer, falling back to [orElse].
int readInt(Object? value, {int orElse = 0}) => readIntOrNull(value) ?? orElse;

/// Reads a number, or null when there is nothing usable.
double? readDoubleOrNull(Object? value) => switch (value) {
  final double d => d,
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

/// Reads a number, falling back to [orElse].
double readDouble(Object? value, {double orElse = 0}) =>
    readDoubleOrNull(value) ?? orElse;

/// Reads a boolean, understanding the several ways WordPress writes one.
bool readBool(Object? value, {bool orElse = false}) => switch (value) {
  final bool b => b,
  'yes' || 'true' || '1' || 1 => true,
  'no' || 'false' || '0' || 0 || '' => false,
  _ => orElse,
};

/// Reads a date, or null. WooCommerce sends local time with no zone on the
/// unsuffixed fields and UTC on the `_gmt` ones; both parse.
DateTime? readDate(Object? value) => switch (value) {
  final String s when s.isNotEmpty => DateTime.tryParse(s),
  _ => null,
};

/// Reads an object, or an empty one.
Map<String, Object?> readMap(Object? value) => switch (value) {
  final Map<String, Object?> m => m,
  final Map<Object?, Object?> m => <String, Object?>{
    for (final MapEntry<Object?, Object?> e in m.entries) '${e.key}': e.value,
  },
  _ => const <String, Object?>{},
};

/// Reads an array, or an empty one.
///
/// WooCommerce sends `[]` for an empty object in a few places, and PHP's
/// `json_encode` turns an associative array into an object — so a field that
/// is a list on one store can be a map on another. Both come back as a list
/// here.
List<Object?> readList(Object? value) => switch (value) {
  final List<Object?> l => l,
  final Map<Object?, Object?> m => m.values.toList(growable: false),
  null => const <Object?>[],
  _ => <Object?>[value],
};

/// Reads an array of objects, skipping anything that is not one.
List<Map<String, Object?>> readObjects(Object? value) => <Map<String, Object?>>[
  for (final Object? e in readList(value))
    if (e is Map<String, Object?>) e,
];

/// Reads a list of integers, tolerating strings among them.
List<int> readInts(Object? value) => <int>[
  for (final Object? e in readList(value))
    if (readIntOrNull(e) case final int i) i,
];

/// Reads a string, falling back to [orElse] when it is absent or empty.
///
/// For fields where an empty string is not a meaningful value — a decimal
/// separator, a default status — and a sensible default beats a blank.
String readStringOr(Object? value, String orElse) {
  final String s = readString(value);
  return s.isEmpty ? orElse : s;
}
