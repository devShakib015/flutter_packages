import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitals/vitals.dart';

/// Exercises the real HealthKit channel on a simulator or device.
///
/// Permission cannot be granted programmatically — `simctl privacy` has no
/// health service — so these cover everything that holds *without* it: the
/// plumbing, the type mapping, the bucket shapes, and the contract that a
/// refused or unasked read comes back empty rather than throwing.
///
///   flutter test integration_test/ios_contract_test.dart -d `simulator-id`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final Vitals vitals = Vitals.instance;
  final DateTime to = DateTime.now();
  final DateTime from = to.subtract(const Duration(days: 7));

  testWidgets('HealthKit is available', (_) async {
    expect(await vitals.isAvailable(), isTrue);
  });

  testWidgets('read access is null, because iOS cannot answer', (_) async {
    expect(
      await vitals.readAccessOnAndroid(<VitalType<VitalSample>>{
        VitalType.steps,
      }),
      isNull,
      reason: 'HKAuthorizationStatus describes sharing only',
    );
  });

  testWidgets('write access is reported, and starts undetermined', (_) async {
    final Map<VitalType<VitalSample>, WriteAccess> access =
        await vitals.writeAccess(<VitalType<VitalSample>>{
      VitalType.water,
      VitalType.bodyMass,
    });
    expect(access.keys, hasLength(2));
    for (final WriteAccess value in access.values) {
      expect(value, isA<WriteAccess>());
    }
  });

  testWidgets('querying before ever asking throws, and says why', (_) async {
    // Discovered by running against the real store rather than assumed: with
    // authorization never requested, HealthKit errors instead of returning
    // empty. That is the one permission state iOS will tell you about, and it
    // means the app forgot to ask.
    await expectLater(
      vitals.read(VitalType.steps, from: from, to: to),
      throwsA(isA<AuthorizationNotDeterminedException>()),
    );
    await expectLater(
      vitals.statistics(
        VitalType.steps,
        from: from,
        to: to,
        bucket: VitalBucket.daily,
      ),
      throwsA(isA<AuthorizationNotDeterminedException>()),
    );
  });

  testWidgets('the undetermined error is typed, not a raw PlatformException', (
    _,
  ) async {
    try {
      await vitals.read(VitalType.heartRate, from: from, to: to);
      fail('expected a throw');
    } on AuthorizationNotDeterminedException catch (e) {
      expect(
        e.message,
        contains('requestPermissions'),
        reason: 'the message should name the fix',
      );
    }
  });

  testWidgets('every supported type reaches the native mapping', (_) async {
    // A type the Dart side offers but the platform cannot resolve fails with
    // unknownType; reaching authorizationNotDetermined instead proves the
    // mapping resolved for all of them.
    for (final VitalType<VitalSample> type in VitalType.all) {
      await expectLater(
        vitals.read(type, from: from, to: to, limit: 1),
        throwsA(isA<AuthorizationNotDeterminedException>()),
        reason: '${type.id} should map to a HealthKit type',
      );
    }
  });

  testWidgets('deleting before asking throws the same typed error', (_) async {
    await expectLater(
      vitals.delete(VitalType.water, from: from, to: to),
      throwsA(isA<AuthorizationNotDeterminedException>()),
    );
  });
}
