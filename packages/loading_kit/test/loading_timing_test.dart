import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

/// The timing policy is the reason this package exists, so it is pinned here
/// rather than left to visual inspection. Every timer runs on the test
/// binding's fake clock, so these assertions cost no real time.
void main() {
  const LoadingTiming timing = LoadingTiming(
    delay: Duration(milliseconds: 140),
    minVisible: Duration(milliseconds: 520),
    successHold: Duration(milliseconds: 300),
    errorHold: Duration(milliseconds: 400),
  );

  LoadingController build() {
    final LoadingController controller = LoadingController(timing: timing);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('an operation faster than the delay never paints', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();

    final Future<void> work = controller.run(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );

    await tester.pump(const Duration(milliseconds: 80));
    expect(
      controller.value.visible,
      isFalse,
      reason: 'resolved inside the reveal delay',
    );

    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.isBusy, isFalse);
    expect(controller.value, LoadingState.idle);
    await work;
  });

  testWidgets('an operation past the delay is held for the minimum window', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();

    final Future<void> work = controller.run(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );

    await tester.pump(const Duration(milliseconds: 139));
    expect(controller.value.visible, isFalse, reason: 'still inside delay');

    await tester.pump(const Duration(milliseconds: 2));
    expect(controller.value.visible, isTrue, reason: 'delay elapsed');

    // Work finished at 200ms but the overlay must survive to 140 + 520 = 660.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.value.visible,
      isTrue,
      reason: 'held by the minimum-visible rule',
    );

    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.value.visible, isFalse);
    await work;
  });

  testWidgets('a fast success shows no check mark', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    final LoadingHandle handle = controller.show(message: 'Saving…');

    await tester.pump(const Duration(milliseconds: 40));
    final Future<void> closed = handle.success('Saved');

    await tester.pump(const Duration(milliseconds: 10));
    expect(
      controller.value.visible,
      isFalse,
      reason: 'never painted, so it leaves no trace',
    );
    expect(handle.isActive, isFalse);
    await closed;
  });

  testWidgets('a visible success holds the check, then leaves', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    final LoadingHandle handle = controller.show(message: 'Saving…');

    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.value.visible, isTrue);

    final Future<void> closed = handle.success('Saved');
    await tester.pump(Duration.zero);
    expect(controller.value.status, LoadingStatus.success);
    expect(controller.value.message, 'Saved');

    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.value.visible, isTrue, reason: 'still holding');

    await tester.pump(const Duration(milliseconds: 150));
    expect(controller.value.visible, isFalse);
    await closed;
  });

  testWidgets('errors hold longer than successes', (WidgetTester tester) async {
    final LoadingController controller = build();
    final LoadingHandle handle = controller.show(message: 'Syncing…');
    await tester.pump(const Duration(milliseconds: 700));

    final Future<void> closed = handle.error('Failed');
    await tester.pump(Duration.zero);
    expect(controller.value.status, LoadingStatus.error);

    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.value.visible, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.value.visible, isFalse);
    await closed;
  });

  testWidgets('LoadingTiming.instant paints and leaves immediately', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = LoadingController(
      timing: LoadingTiming.instant,
    );
    addTearDown(controller.dispose);

    final LoadingHandle handle = controller.show();
    expect(controller.value.visible, isTrue, reason: 'no reveal delay');

    final Future<void> closed = handle.dismiss();
    await tester.pump(Duration.zero);
    expect(controller.value.visible, isFalse);
    await closed;
  });
}
