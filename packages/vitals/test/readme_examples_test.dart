// Type-checks the README's write examples against the real API.
//
// 0.1.2 documented `writeMass(type, 71.2, unit: Mass.kilograms)` and
// `writeCount(..., at:)`, neither of which exists — the unit is carried by the
// value type, and counts take a period. A syntax check cannot catch a wrong
// signature, so the examples live here as code and the compiler checks them.
// This file existing and compiling *is* the test.
// ignore_for_file: unused_element
import 'package:flutter_test/flutter_test.dart';
import 'package:vitals/vitals.dart';

void main() {
  test('the README write examples match the real API', () {
    // Compiling is the assertion; calling them would need a live HealthKit.
    expect(_readmeWriteExamples, isA<Function>());
  });
}

Future<void> _readmeWriteExamples() async {
  final Vitals vitals = Vitals.instance;
  final DateTime now = DateTime.now();
  final DateTime earlier = now.subtract(const Duration(hours: 1));

  // A tally over a period.
  await vitals.writeCount(VitalType.steps, 2400, from: earlier, to: now);

  // A measurement at an instant. The unit is part of the value.
  await vitals.writeMass(
    VitalType.bodyMass,
    const Mass.kilograms(71.2),
    at: now,
  );
  await vitals.writeVolume(
    VitalType.water,
    const Volume.millilitres(250),
    at: now,
  );

  // A quantity accumulated over a period.
  await vitals.writeLength(
    VitalType.distanceWalkingRunning,
    const Length.metres(1800),
    from: earlier,
    to: now,
  );
  await vitals.writeEnergy(
    VitalType.activeEnergyBurned,
    const Energy.kilocalories(180),
    from: earlier,
    to: now,
  );

  // Plain numbers where there is only one sensible unit.
  await vitals.writeRate(VitalType.heartRate, 62, at: now);
  await vitals.writePercent(VitalType.oxygenSaturation, 0.98, at: now);
}
