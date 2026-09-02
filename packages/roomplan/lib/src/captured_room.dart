import 'dart:convert';

/// A point or extent in metres, in RoomPlan's right-handed space.
class Vector3 {
  /// Creates a vector.
  const Vector3(this.x, this.y, this.z);

  /// Zero.
  static const Vector3 zero = Vector3(0, 0, 0);

  /// Builds from a JSON list, tolerating a missing or short one.
  factory Vector3.fromJson(Object? value) {
    if (value is! List || value.length < 3) return zero;
    double at(int i) => (value[i] as num?)?.toDouble() ?? 0;
    return Vector3(at(0), at(1), at(2));
  }

  /// Extent or position along x, in metres.
  final double x;

  /// Extent or position along y, in metres.
  final double y;

  /// Extent or position along z, in metres.
  final double z;

  @override
  String toString() =>
      'Vector3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, '
      '${z.toStringAsFixed(3)})';
}

/// One flat element of a room — a wall, door, window or opening.
class RoomSurface {
  /// Creates a surface.
  const RoomSurface({
    required this.identifier,
    required this.dimensions,
    required this.transform,
    required this.category,
    required this.confidence,
  });

  /// Builds a surface from RoomPlan's encoding.
  factory RoomSurface.fromJson(Map<String, Object?> json) => RoomSurface(
        identifier: json['identifier']?.toString() ?? '',
        dimensions: Vector3.fromJson(json['dimensions']),
        transform: _matrix(json['transform']),
        category: _categoryOf(json['category']),
        confidence: json['confidence']?.toString(),
      );

  /// Stable id for this element within the scan.
  final String identifier;

  /// Width, height and depth in metres.
  final Vector3 dimensions;

  /// A 4x4 column-major transform, 16 values, or empty if absent.
  final List<double> transform;

  /// `wall`, `door`, `window`, `opening`, `floor`, or whatever RoomPlan said.
  final String category;

  /// RoomPlan's own confidence, when it reported one.
  final String? confidence;

  /// The element's position in metres, read out of [transform].
  Vector3 get position => transform.length == 16
      ? Vector3(transform[12], transform[13], transform[14])
      : Vector3.zero;

  @override
  String toString() => 'RoomSurface($category, $dimensions)';
}

/// A piece of furniture or fitting RoomPlan recognised.
class RoomObject {
  /// Creates an object.
  const RoomObject({
    required this.identifier,
    required this.dimensions,
    required this.transform,
    required this.category,
    required this.confidence,
  });

  /// Builds an object from RoomPlan's encoding.
  factory RoomObject.fromJson(Map<String, Object?> json) => RoomObject(
        identifier: json['identifier']?.toString() ?? '',
        dimensions: Vector3.fromJson(json['dimensions']),
        transform: _matrix(json['transform']),
        category: _categoryOf(json['category']),
        confidence: json['confidence']?.toString(),
      );

  /// Stable id for this object within the scan.
  final String identifier;

  /// Width, height and depth in metres.
  final Vector3 dimensions;

  /// A 4x4 column-major transform, 16 values, or empty if absent.
  final List<double> transform;

  /// `chair`, `table`, `bed`, `storage`, and so on.
  final String category;

  /// RoomPlan's own confidence, when it reported one.
  final String? confidence;

  /// The object's position in metres, read out of [transform].
  Vector3 get position => transform.length == 16
      ? Vector3(transform[12], transform[13], transform[14])
      : Vector3.zero;

  @override
  String toString() => 'RoomObject($category, $dimensions)';
}

/// A finished scan.
///
/// **[raw] is the guaranteed part of this API.** It is RoomPlan's own encoding
/// of `CapturedRoom`, decoded but otherwise untouched. The typed lists below
/// are a convenience read out of it, and they are deliberately forgiving: a
/// field RoomPlan renames or adds will leave them thinner rather than throwing,
/// and everything is still in [raw]. If a value matters to you and the typed
/// accessor does not have it, read [raw] and open an issue.
class CapturedRoom {
  /// Creates a captured room.
  const CapturedRoom({
    required this.walls,
    required this.doors,
    required this.windows,
    required this.openings,
    required this.floors,
    required this.objects,
    required this.raw,
    required this.usdzPath,
  });

  /// Parses RoomPlan's JSON.
  factory CapturedRoom.fromJson(String source, {String? usdzPath}) {
    final Object? decoded = jsonDecode(source);
    final Map<String, Object?> map =
        decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    List<RoomSurface> surfaces(String key) =>
        _listOf(map[key]).map(RoomSurface.fromJson).toList(growable: false);
    return CapturedRoom(
      walls: surfaces('walls'),
      doors: surfaces('doors'),
      windows: surfaces('windows'),
      openings: surfaces('openings'),
      floors: surfaces('floors'),
      objects: _listOf(map['objects'])
          .map(RoomObject.fromJson)
          .toList(growable: false),
      raw: map,
      usdzPath: usdzPath,
    );
  }

  /// The room's walls.
  final List<RoomSurface> walls;

  /// Doorways found in the walls.
  final List<RoomSurface> doors;

  /// Windows found in the walls.
  final List<RoomSurface> windows;

  /// Wall openings that are neither doors nor windows.
  final List<RoomSurface> openings;

  /// Floor surfaces.
  final List<RoomSurface> floors;

  /// Recognised furniture and fittings.
  final List<RoomObject> objects;

  /// RoomPlan's own encoding, decoded but not reshaped.
  final Map<String, Object?> raw;

  /// Where the USDZ model was written, if the export succeeded.
  final String? usdzPath;

  /// Every flat element, in one list.
  List<RoomSurface> get surfaces => <RoomSurface>[
        ...walls,
        ...doors,
        ...windows,
        ...openings,
        ...floors,
      ];

  @override
  String toString() =>
      'CapturedRoom(${walls.length} walls, ${doors.length} doors, '
      '${windows.length} windows, ${objects.length} objects)';
}

List<Map<String, Object?>> _listOf(Object? value) => value is List
    ? value.whereType<Map<String, Object?>>().toList(growable: false)
    : const <Map<String, Object?>>[];

List<double> _matrix(Object? value) {
  // RoomPlan encodes a simd_float4x4 as four columns of four, but a flat
  // sixteen is just as plausible a shape, so accept either.
  if (value is! List) return const <double>[];
  final List<double> out = <double>[];
  for (final Object? entry in value) {
    if (entry is num) {
      out.add(entry.toDouble());
    } else if (entry is List) {
      out.addAll(entry.whereType<num>().map((num n) => n.toDouble()));
    }
  }
  return out.length == 16 ? out : const <double>[];
}

String _categoryOf(Object? value) {
  if (value is String) return value;
  // Swift encodes an enum with an associated value as a single-key object.
  if (value is Map && value.keys.length == 1) {
    return value.keys.first.toString();
  }
  return 'unknown';
}
