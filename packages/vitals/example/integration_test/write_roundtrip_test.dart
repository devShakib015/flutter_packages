// Verifies the write path end to end on a device or Simulator.
//
//   flutter test integration_test/write_roundtrip_test.dart -d <device>
//
// Requires HealthKit write permission to have been granted already — the
// permission sheet needs a human, so run the example once and grant it first.
// This is the test that would have caught the missing entitlement: it fails
// with "Not authorized" when the app is built without one.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitals/vitals.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('a written sample reads back with the same value and unit', () async {
    final Vitals vitals = Vitals.instance;
    expect(await vitals.isAvailable(), isTrue);

    final Map<VitalType<VitalSample>, WriteAccess> access =
        await vitals.writeAccess(<VitalType<VitalSample>>{VitalType.water});
    // ignore: avoid_print
    print('  write access for water: ${access[VitalType.water]}');
    if (access[VitalType.water] != WriteAccess.granted) {
      // ignore: avoid_print
      print('  SKIPPED — run the example and grant water write first');
      return;
    }

    final DateTime at = DateTime.now();
    final DateTime from = at.subtract(const Duration(minutes: 1));
    final DateTime to = at.add(const Duration(minutes: 1));

    final List<VolumeSample> before = await vitals.read(
      VitalType.water,
      from: from,
      to: to,
    );
    await vitals.writeVolume(
      VitalType.water,
      const Volume.millilitres(250),
      at: at,
    );
    final List<VolumeSample> after = await vitals.read(
      VitalType.water,
      from: from,
      to: to,
    );

    // ignore: avoid_print
    print('  samples before ${before.length}, after ${after.length}');
    expect(
      after.length,
      before.length + 1,
      reason: 'the written sample should be readable',
    );

    final double written = after
        .map((VolumeSample s) => s.value.millilitres)
        .reduce((double a, double b) => a > b ? a : b);
    // A unit-conversion mistake would be silent, which is exactly why this
    // asserts the value rather than only the count.
    expect(written, closeTo(250, 0.001));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
