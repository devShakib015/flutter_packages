// Renders the README image for RoomFloorPlan.
//
// Driven by `flutter test` because that gives a rasterizer. The room is sample
// geometry, not a real scan — RoomPlan needs LiDAR, and this repo does not
// fake hardware it does not have. What the picture shows is the floor-plan
// widget, which is real and covered by tests.
//
//   flutter test tool/record_frames.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomplan/roomplan.dart';

final GlobalKey _stage = GlobalKey();

/// Column-major 4x4 for a thing at (x, z) facing (dirX, dirZ).
List<double> _at(double x, double z, {double dirX = 1, double dirZ = 0}) =>
    <double>[dirX, 0, dirZ, 0, 0, 1, 0, 0, -dirZ, 0, dirX, 0, x, 0, z, 1];

Map<String, Object?> _surface(
  List<double> dimensions,
  List<double> transform, [
  String? category,
]) =>
    <String, Object?>{
      'dimensions': dimensions,
      'transform': transform,
      if (category != null) 'category': category,
    };

/// A plausible living room: five metres by four, with a door, two windows and
/// some furniture.
CapturedRoom sampleRoom() => CapturedRoom.fromJson(
      jsonEncode(<String, Object?>{
        'walls': <Object?>[
          _surface(<double>[5, 2.5, .1], _at(0, -2)),
          _surface(<double>[5, 2.5, .1], _at(0, 2)),
          _surface(<double>[4, 2.5, .1], _at(-2.5, 0, dirX: 0, dirZ: 1)),
          _surface(<double>[4, 2.5, .1], _at(2.5, 0, dirX: 0, dirZ: 1)),
        ],
        'doors': <Object?>[
          _surface(<double>[0.9, 2.1, .1], _at(-1.4, 2)),
        ],
        'windows': <Object?>[
          _surface(<double>[1.4, 1.2, .1], _at(0.6, -2)),
          _surface(<double>[1.0, 1.2, .1], _at(-2.5, -0.6, dirX: 0, dirZ: 1)),
        ],
        'objects': <Object?>[
          _surface(<double>[2.1, 0.8, 0.9], _at(0, -1.2), 'sofa'),
          _surface(<double>[1.1, 0.4, 0.6], _at(0, -0.1), 'table'),
          _surface(<double>[0.7, 0.9, 0.7], _at(-1.9, 0.9), 'chair'),
          _surface(
            <double>[1.6, 0.5, 0.4],
            _at(1.8, 0.9, dirX: 0, dirZ: 1),
            'storage',
          ),
        ],
      }),
    );

void main() {
  setUpAll(() async {
    final Uint8List bytes =
        File('tool/fonts/InterVariable.ttf').readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');
  });

  testWidgets('render: floor plan', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(520, 420));
    await tester.pumpWidget(_Stage(room: sampleRoom()));
    await tester.pumpAndSettle();

    final Directory out = Directory('doc')..createSync(recursive: true);
    await tester.runAsync(() async {
      RenderObject? obj = tester.renderObject(find.byKey(_stage));
      while (obj != null && !obj.isRepaintBoundary) {
        obj = obj.parent;
      }
      final ui.Image image = await (obj!.debugLayer! as OffsetLayer).toImage(
        obj.paintBounds,
        pixelRatio: 2,
      );
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (png != null) {
        File('${out.path}/floor_plan.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });
    // ignore: avoid_print
    print('wrote doc/floor_plan.png');
    await tester.binding.setSurfaceSize(null);
  });
}

class _Stage extends StatelessWidget {
  const _Stage({required this.room});

  final CapturedRoom room;

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0B0F17);
    const Color panel = Color(0xFF141A24);
    const Color text = Color(0xFFE6EDF3);
    const Color muted = Color(0xFF7D8590);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: RepaintBoundary(
        key: _stage,
        child: Material(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'RoomFloorPlan',
                  style: TextStyle(
                    color: text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${room.walls.length} walls · ${room.doors.length} door · '
                  '${room.windows.length} windows · '
                  '${room.objects.length} objects',
                  style: const TextStyle(color: muted, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: panel,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: RoomFloorPlan(
                        room: room,
                        style: const FloorPlanStyle(
                          wall: Color(0xFFE6EDF3),
                          door: Color(0xFF34D399),
                          window: Color(0xFF7C9CFF),
                          object: Color(0x2E7C9CFF),
                          objectOutline: Color(0xFF7D8590),
                          wallThickness: 5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
