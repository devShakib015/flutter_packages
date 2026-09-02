// Each test pins a defect found by the 2026-09-02 audit.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roomplan/roomplan.dart';

void main() {
  testWidgets('a non-iOS platform shows the fallback, not a black view', (
    WidgetTester tester,
  ) async {
    // Also proves dart:io is gone: this used to be `Platform.isIOS`, which
    // made the package impossible to compile for web at all — while the
    // kIsWeb guards claimed it was safe there.
    final RoomScanController controller = RoomScanController();
    addTearDown(controller.dispose);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RoomScanView(
              controller: controller,
              fallback: const Text('no scanning here'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('no scanning here'), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
    } finally {
      // Must be reset inside the body: the framework checks for a leaked
      // debug variable before addTearDown callbacks run.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('isSupportedPlatform follows the target platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(RoomScanView.isSupportedPlatform, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(RoomScanView.isSupportedPlatform, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  group('a floor plan redraws when its style changes', () {
    test('FloorPlanStyle compares by value', () {
      // Shipped in 0.2.0: FloorPlanStyle had identity equality, so
      // shouldRepaint could not see a change and a theme switch redrew
      // nothing.
      const FloorPlanStyle a = FloorPlanStyle();
      const FloorPlanStyle b = FloorPlanStyle();
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      const FloorPlanStyle dark = FloorPlanStyle(wall: Color(0xFFFFFFFF));
      expect(a, isNot(dark));

      const FloorPlanStyle thick = FloorPlanStyle(wallThickness: 9);
      expect(a, isNot(thick));
    });

    testWidgets('the widget repaints on a style change', (
      WidgetTester tester,
    ) async {
      const CapturedRoom room = CapturedRoom(
        walls: <RoomSurface>[],
        doors: <RoomSurface>[],
        windows: <RoomSurface>[],
        openings: <RoomSurface>[],
        floors: <RoomSurface>[],
        objects: <RoomObject>[],
        raw: <String, Object?>{},
        usdzPath: null,
      );

      Widget plan(FloorPlanStyle style) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: RoomFloorPlan(room: room, style: style),
          ),
        ),
      );

      await tester.pumpWidget(plan(const FloorPlanStyle()));
      await tester.pumpWidget(
        plan(const FloorPlanStyle(wall: Color(0xFFFF0000))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
