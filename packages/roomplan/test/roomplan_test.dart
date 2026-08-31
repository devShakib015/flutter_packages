import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomplan/roomplan.dart';

/// Shaped the way RoomPlan encodes `CapturedRoom`: simd vectors as flat lists,
/// a 4x4 as four columns, categories as single-key objects for the cases that
/// carry an associated value.
String sampleRoom() => jsonEncode(<String, Object?>{
  'walls': <Object?>[
    <String, Object?>{
      'identifier': 'wall-1',
      'dimensions': <double>[3.2, 2.4, 0.1],
      'transform': <List<double>>[
        <double>[1, 0, 0, 0],
        <double>[0, 1, 0, 0],
        <double>[0, 0, 1, 0],
        <double>[1.5, 0, -2.0, 1],
      ],
      'category': 'wall',
      'confidence': 'high',
    },
  ],
  'doors': <Object?>[
    <String, Object?>{
      'identifier': 'door-1',
      'dimensions': <double>[0.9, 2.0, 0.05],
      'category': <String, Object?>{'door': <String, Object?>{}},
    },
  ],
  'windows': <Object?>[],
  'openings': <Object?>[],
  'floors': <Object?>[
    <String, Object?>{
      'identifier': 'floor-1',
      'dimensions': <double>[4, 0.1, 5],
    },
  ],
  'objects': <Object?>[
    <String, Object?>{
      'identifier': 'obj-1',
      'dimensions': <double>[0.6, 0.9, 0.6],
      'category': <String, Object?>{'chair': <String, Object?>{}},
      'confidence': 'medium',
    },
  ],
  'version': 3,
});

void main() {
  _floorPlanTests();
  group('parsing a scan', () {
    test('reads the room into typed lists', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      expect(room.walls, hasLength(1));
      expect(room.doors, hasLength(1));
      expect(room.floors, hasLength(1));
      expect(room.objects, hasLength(1));
      expect(room.windows, isEmpty);
      expect(room.surfaces, hasLength(3)); // wall + door + floor
    });

    test('dimensions are metres, in order', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      final Vector3 d = room.walls.single.dimensions;
      expect(d.x, closeTo(3.2, 1e-9));
      expect(d.y, closeTo(2.4, 1e-9));
      expect(d.z, closeTo(0.1, 1e-9));
    });

    test('position is read out of the transform, not invented', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      final Vector3 p = room.walls.single.position;
      // Column-major: translation lives in the fourth column.
      expect(p.x, closeTo(1.5, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
      expect(p.z, closeTo(-2.0, 1e-9));
    });

    test('a category encoded as a single-key object is unwrapped', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      expect(room.objects.single.category, 'chair');
      expect(room.doors.single.category, 'door');
      // A plain string still works.
      expect(room.walls.single.category, 'wall');
    });

    test('the raw encoding is kept whole', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      // The typed model does not cover `version`; raw must still have it.
      expect(room.raw['version'], 3);
    });

    test('the usdz path rides along when the export worked', () {
      final CapturedRoom room = CapturedRoom.fromJson(
        sampleRoom(),
        usdzPath: '/tmp/room.usdz',
      );
      expect(room.usdzPath, '/tmp/room.usdz');
    });
  });

  group('tolerating what RoomPlan actually sends', () {
    // The typed model is a convenience over an encoding this package cannot
    // execute without LiDAR hardware. It has to bend rather than break.
    test('a flat sixteen-value matrix parses the same as four columns', () {
      final String flat = jsonEncode(<String, Object?>{
        'walls': <Object?>[
          <String, Object?>{
            'transform': <double>[
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              0,
              1,
              0,
              7,
              8,
              9,
              1,
            ],
          },
        ],
      });
      expect(CapturedRoom.fromJson(flat).walls.single.position.x, 7);
    });

    test('a missing transform yields zero, not a crash', () {
      final CapturedRoom room = CapturedRoom.fromJson(sampleRoom());
      expect(room.doors.single.transform, isEmpty);
      expect(room.doors.single.position.x, 0);
    });

    test('an unknown category degrades to a label, not an exception', () {
      final String odd = jsonEncode(<String, Object?>{
        'objects': <Object?>[
          <String, Object?>{'category': 42},
        ],
      });
      expect(CapturedRoom.fromJson(odd).objects.single.category, 'unknown');
    });

    test('entirely unexpected json produces an empty room', () {
      expect(CapturedRoom.fromJson('[]').walls, isEmpty);
      expect(CapturedRoom.fromJson('{}').objects, isEmpty);
      expect(CapturedRoom.fromJson('{"walls": "not a list"}').walls, isEmpty);
    });

    test('a short dimensions list does not throw', () {
      final String short = jsonEncode(<String, Object?>{
        'walls': <Object?>[
          <String, Object?>{
            'dimensions': <double>[1, 2],
          },
        ],
      });
      expect(
        CapturedRoom.fromJson(short).walls.single.dimensions,
        Vector3.zero,
      );
    });
  });

  group('support', () {
    test('no LiDAR is a different answer from an old OS', () {
      final RoomScanSupport a = RoomScanSupport.fromMap(<Object?, Object?>{
        'supported': false,
        'reason': 'noLidar',
      });
      final RoomScanSupport b = RoomScanSupport.fromMap(<Object?, Object?>{
        'supported': false,
        'reason': 'osTooOld',
      });
      expect(a.reason, RoomScanUnsupportedReason.noLidar);
      expect(b.reason, RoomScanUnsupportedReason.osTooOld);
      expect(a.reason == b.reason, isFalse);
    });

    test('a supported device says so', () {
      final RoomScanSupport s = RoomScanSupport.fromMap(<Object?, Object?>{
        'supported': true,
        'reason': 'supported',
      });
      expect(s.supported, isTrue);
      expect(s.reason, RoomScanUnsupportedReason.supported);
    });
  });

  group('controller', () {
    test('says so when it is not attached', () {
      final RoomScanController c = RoomScanController();
      addTearDown(c.dispose);
      expect(c.isAttached, isFalse);
      expect(c.isScanning, isFalse);
      expect(c.start, throwsStateError);
      expect(c.stop, throwsStateError);
    });

    test('delivers a room when the view reports one', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const MethodChannel channel = MethodChannel('dev.shakib/roomplan/scan/1');
      final RoomScanController c = RoomScanController()..attach(channel);
      addTearDown(c.dispose);

      final Future<CapturedRoom> next = c.rooms.first;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('event', <Object?, Object?>{
                'type': 'room',
                'json': sampleRoom(),
                'usdz': '/tmp/a.usdz',
              }),
            ),
            (_) {},
          );
      final CapturedRoom room = await next;
      expect(room.walls, hasLength(1));
      expect(room.usdzPath, '/tmp/a.usdz');
      expect(c.isScanning, isFalse);
    });

    test('surfaces a scan error rather than swallowing it', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const MethodChannel channel = MethodChannel('dev.shakib/roomplan/scan/2');
      final RoomScanController c = RoomScanController()..attach(channel);
      addTearDown(c.dispose);

      final Future<String> next = c.errors.first;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            channel.codec.encodeMethodCall(
              MethodCall('event', <Object?, Object?>{
                'type': 'error',
                'message': 'Insufficient lighting.',
              }),
            ),
            (_) {},
          );
      expect(await next, 'Insufficient lighting.');
    });
  });
}

void _floorPlanTests() {
  /// A small square room with one door, one window and a table, laid out so
  /// the expected geometry can be reasoned about by hand.
  CapturedRoom squareRoom() {
    List<double> at(double x, double z, {double dirX = 1, double dirZ = 0}) =>
        <double>[dirX, 0, dirZ, 0, 0, 1, 0, 0, -dirZ, 0, dirX, 0, x, 0, z, 1];
    return CapturedRoom.fromJson(
      jsonEncode(<String, Object?>{
        'walls': <Object?>[
          <String, Object?>{
            'dimensions': <double>[4, 2.4, .1],
            'transform': at(0, -2),
          },
          <String, Object?>{
            'dimensions': <double>[4, 2.4, .1],
            'transform': at(0, 2),
          },
          <String, Object?>{
            'dimensions': <double>[4, 2.4, .1],
            'transform': at(-2, 0, dirX: 0, dirZ: 1),
          },
          <String, Object?>{
            'dimensions': <double>[4, 2.4, .1],
            'transform': at(2, 0, dirX: 0, dirZ: 1),
          },
        ],
        'doors': <Object?>[
          <String, Object?>{
            'dimensions': <double>[0.9, 2, .1],
            'transform': at(-1, -2),
          },
        ],
        'windows': <Object?>[
          <String, Object?>{
            'dimensions': <double>[1.2, 1, .1],
            'transform': at(1, 2),
          },
        ],
        'objects': <Object?>[
          <String, Object?>{
            'dimensions': <double>[1.2, 0.75, 0.8],
            'transform': at(0, 0),
            'category': <String, Object?>{'table': <String, Object?>{}},
          },
        ],
      }),
    );
  }

  group('floor plan', () {
    testWidgets('draws a room without throwing', (WidgetTester tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 300,
            child: RoomFloorPlan(room: squareRoom()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(RoomFloorPlan), findsOneWidget);
    });

    testWidgets('an empty room paints nothing and does not crash', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: RoomFloorPlan(room: CapturedRoom.fromJson('{}')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives surfaces with no usable transform', (
      WidgetTester tester,
    ) async {
      final CapturedRoom broken = CapturedRoom.fromJson(
        jsonEncode(<String, Object?>{
          'walls': <Object?>[
            <String, Object?>{
              'dimensions': <double>[3, 2, .1],
            }, // no transform
          ],
        }),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 200,
            height: 200,
            child: RoomFloorPlan(room: broken),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at any size, including very small', (
      WidgetTester tester,
    ) async {
      for (final Size size in <Size>[
        const Size(40, 30),
        const Size(200, 200),
        const Size(800, 200),
      ]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: RoomFloorPlan(room: squareRoom()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('hiding objects still draws the shell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 300,
            height: 300,
            child: RoomFloorPlan(room: squareRoom(), showObjects: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
