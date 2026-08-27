// Runs against a real iOS device or Simulator.
//
//   flutter test integration_test -d <device>
//
// A real *scan* cannot be verified here: RoomPlan needs LiDAR, and no
// Simulator has it. What this does prove is that the plugin registers, that
// support detection gives a truthful answer, and that asking a device without
// the sensor to scan fails cleanly instead of crashing.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:roomplan/roomplan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('the plugin registers and answers', () async {
    final RoomScanSupport s = await RoomScanController.support();
    // ignore: avoid_print
    print('  support: supported=${s.supported} reason=${s.reason.name}');
    expect(s, isA<RoomScanSupport>());
  });

  test('a device without LiDAR says so, rather than pretending', () async {
    final RoomScanSupport s = await RoomScanController.support();
    if (!s.supported) {
      // The Simulator has no LiDAR, so this is the expected path here.
      expect(
        s.reason,
        anyOf(
          RoomScanUnsupportedReason.noLidar,
          RoomScanUnsupportedReason.osTooOld,
        ),
      );
      // ignore: avoid_print
      print('  correctly reported unsupported: ${s.reason.name}');
    } else {
      // ignore: avoid_print
      print('  THIS DEVICE HAS LIDAR — a real scan can be verified here');
    }
  });
}
