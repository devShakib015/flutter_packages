import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'captured_room.dart';

/// Colours and weights for a [RoomFloorPlan].
class FloorPlanStyle {
  /// Creates a style.
  const FloorPlanStyle({
    this.wall = const Color(0xFF1F2937),
    this.door = const Color(0xFF2563EB),
    this.window = const Color(0xFF0EA5E9),
    this.opening = const Color(0xFF94A3B8),
    this.object = const Color(0x332563EB),
    this.objectOutline = const Color(0xFF64748B),
    this.wallThickness = 4,
    this.detailThickness = 4,
    this.padding = 16,
  });

  /// Colour of walls.
  final Color wall;

  /// Colour of doorways.
  final Color door;

  /// Colour of windows.
  final Color window;

  /// Colour of openings that are neither doors nor windows.
  final Color opening;

  /// Fill for recognised furniture.
  final Color object;

  /// Outline for recognised furniture.
  final Color objectOutline;

  /// Stroke width for walls.
  final double wallThickness;

  /// Stroke width for doors, windows and openings.
  final double detailThickness;

  /// Space left around the plan, in logical pixels.
  final double padding;

  @override
  bool operator ==(Object other) =>
      other is FloorPlanStyle &&
      other.wall == wall &&
      other.door == door &&
      other.window == window &&
      other.opening == opening &&
      other.object == object &&
      other.objectOutline == objectOutline &&
      other.wallThickness == wallThickness &&
      other.detailThickness == detailThickness &&
      other.padding == padding;

  @override
  int get hashCode => Object.hash(
        wall,
        door,
        window,
        opening,
        object,
        objectOutline,
        wallThickness,
        detailThickness,
        padding,
      );
}

/// Draws a scanned room as a top-down floor plan.
///
/// A [CapturedRoom] is geometry: transforms and extents in metres. Useful, but
/// not something a person can look at. This projects it onto the floor plane
/// and draws it, which is usually the first thing an app wants to do with a
/// scan and is fiddly enough — column-major transforms, metres to pixels,
/// fitting to the widget — to be worth doing once, here.
///
/// The plan is scaled to fit and centred, so it works at any size.
class RoomFloorPlan extends StatelessWidget {
  /// Creates a floor plan.
  const RoomFloorPlan({
    super.key,
    required this.room,
    this.style = const FloorPlanStyle(),
    this.showObjects = true,
  });

  /// The scan to draw.
  final CapturedRoom room;

  /// How it should look.
  final FloorPlanStyle style;

  /// Whether to draw recognised furniture as well as the shell.
  final bool showObjects;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _FloorPlanPainter(
          room: room,
          style: style,
          showObjects: showObjects,
        ),
        size: Size.infinite,
      );
}

/// A surface reduced to the line it occupies on the floor.
class _Segment {
  const _Segment(this.a, this.b, this.colour, this.width);
  final Offset a;
  final Offset b;
  final Color colour;
  final double width;
}

class _FloorPlanPainter extends CustomPainter {
  _FloorPlanPainter({
    required this.room,
    required this.style,
    required this.showObjects,
  });

  final CapturedRoom room;
  final FloorPlanStyle style;
  final bool showObjects;

  @override
  void paint(Canvas canvas, Size size) {
    final List<_Segment> segments = <_Segment>[
      for (final RoomSurface w in room.walls)
        ..._segment(w, style.wall, style.wallThickness),
      for (final RoomSurface d in room.doors)
        ..._segment(d, style.door, style.detailThickness),
      for (final RoomSurface w in room.windows)
        ..._segment(w, style.window, style.detailThickness),
      for (final RoomSurface o in room.openings)
        ..._segment(o, style.opening, style.detailThickness),
    ];
    final List<(List<Offset>, RoomObject)> boxes = showObjects
        ? <(List<Offset>, RoomObject)>[
            for (final RoomObject o in room.objects)
              if (_footprint(o) case final List<Offset> corners
                  when corners.isNotEmpty)
                (corners, o),
          ]
        : const <(List<Offset>, RoomObject)>[];

    final List<Offset> all = <Offset>[
      for (final _Segment s in segments) ...<Offset>[s.a, s.b],
      for (final (List<Offset> corners, _) in boxes) ...corners,
    ];
    if (all.isEmpty) return;

    // Fit the plan to the widget, uniformly, so proportions survive.
    double minX = all.first.dx, maxX = all.first.dx;
    double minY = all.first.dy, maxY = all.first.dy;
    for (final Offset p in all) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final double spanX = math.max(maxX - minX, 0.001);
    final double spanY = math.max(maxY - minY, 0.001);
    final double usableW = math.max(size.width - style.padding * 2, 1);
    final double usableH = math.max(size.height - style.padding * 2, 1);
    final double scale = math.min(usableW / spanX, usableH / spanY);
    final double offsetX = (size.width - spanX * scale) / 2 - minX * scale;
    final double offsetY = (size.height - spanY * scale) / 2 - minY * scale;
    Offset place(Offset p) =>
        Offset(p.dx * scale + offsetX, p.dy * scale + offsetY);

    for (final (List<Offset> corners, RoomObject _) in boxes) {
      final Path path = Path()
        ..addPolygon(corners.map(place).toList(growable: false), true);
      canvas.drawPath(path, Paint()..color = style.object);
      canvas.drawPath(
        path,
        Paint()
          ..color = style.objectOutline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    for (final _Segment s in segments) {
      canvas.drawLine(
        place(s.a),
        place(s.b),
        Paint()
          ..color = s.colour
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// A wall seen from above is the line its width traces on the floor.
  ///
  /// The transform is column-major, so its first column is the surface's own
  /// x-axis and its fourth is the translation. Dropping the y components
  /// projects onto the floor.
  List<_Segment> _segment(RoomSurface s, Color colour, double width) {
    final List<double> m = s.transform;
    if (m.length != 16) return const <_Segment>[];
    final Offset centre = Offset(m[12], m[14]);
    final double dirX = m[0], dirZ = m[2];
    final double length = math.sqrt(dirX * dirX + dirZ * dirZ);
    if (length < 1e-6) return const <_Segment>[];
    final Offset unit = Offset(dirX / length, dirZ / length);
    final Offset half = unit * (s.dimensions.x / 2);
    return <_Segment>[_Segment(centre - half, centre + half, colour, width)];
  }

  /// An object's footprint: its width and depth, rotated and placed.
  List<Offset> _footprint(RoomObject o) {
    final List<double> m = o.transform;
    if (m.length != 16) return const <Offset>[];
    final Offset centre = Offset(m[12], m[14]);
    final double lenX = math.sqrt(m[0] * m[0] + m[2] * m[2]);
    final double lenZ = math.sqrt(m[8] * m[8] + m[10] * m[10]);
    if (lenX < 1e-6 || lenZ < 1e-6) return const <Offset>[];
    final Offset ux = Offset(m[0] / lenX, m[2] / lenX) * (o.dimensions.x / 2);
    final Offset uz = Offset(m[8] / lenZ, m[10] / lenZ) * (o.dimensions.z / 2);
    return <Offset>[
      centre - ux - uz,
      centre + ux - uz,
      centre + ux + uz,
      centre - ux + uz,
    ];
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) =>
      old.room != room ||
      old.showObjects != showObjects ||
      // Without this a floor plan kept its old colours and stroke widths
      // forever — switching to a dark theme redrew nothing.
      old.style != style;
}
