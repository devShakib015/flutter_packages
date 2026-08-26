import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

void main() {
  const LoadingTiming timing = LoadingTiming(
    delay: Duration(milliseconds: 100),
    minVisible: Duration(milliseconds: 200),
    successHold: Duration(milliseconds: 200),
    errorHold: Duration(milliseconds: 200),
  );

  LoadingController build() {
    final LoadingController controller = LoadingController(timing: timing);
    addTearDown(controller.dispose);
    return controller;
  }

  group('reference counting', () {
    testWidgets('the overlay outlives the first request to finish', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();

      final LoadingHandle a = controller.show(message: 'A');
      final LoadingHandle b = controller.show(message: 'B');
      await tester.pump(const Duration(milliseconds: 150));

      expect(controller.value.visible, isTrue);
      expect(controller.value.depth, 2);

      final Future<void> closedA = a.dismiss();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.value.visible, isTrue,
          reason: 'B is still in flight');
      expect(controller.value.depth, 1);
      await closedA;

      final Future<void> closedB = b.dismiss();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.value.visible, isFalse);
      await closedB;
    });

    testWidgets('a running operation outranks one that already settled', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();

      final LoadingHandle a = controller.show(message: 'A');
      controller.show(message: 'B');
      await tester.pump(const Duration(milliseconds: 150));

      unawaited(a.success('A done'));
      await tester.pump(Duration.zero);

      expect(controller.value.status, LoadingStatus.busy,
          reason: 'B is still busy, so no check mark flashes');
      expect(controller.value.message, 'B');
      controller.dispose();
    });
  });

  group('run', () {
    testWidgets('returns the task result', (WidgetTester tester) async {
      final LoadingController controller = build();
      final Future<int> work = controller.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return 42;
      });
      await tester.pump(const Duration(milliseconds: 800));
      expect(await work, 42);
    });

    testWidgets('rethrows and still tears the overlay down', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      // Subscribe before pumping: the future rejects mid-pump, and an
      // unsubscribed rejection is reported as an unhandled zone error.
      final Future<void> expectation = expectLater(
        controller.run<void>(
          () async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            throw StateError('boom');
          },
          message: 'Working…',
          errorMessage: 'Failed',
        ),
        throwsStateError,
      );

      await tester.pump(const Duration(milliseconds: 900));
      await expectation;
      expect(controller.isBusy, isFalse);
    });

    testWidgets('a timeout surfaces as TimeoutException', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      final Future<void> expectation = expectLater(
        controller.run<void>(
          () => Future<void>.delayed(const Duration(seconds: 1)),
          timeout: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await expectation;
      expect(controller.isBusy, isFalse);
      // Timing out abandons the work rather than killing it — Dart has no way
      // to kill a future. Let it finish so no timer outlives the test.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('runTask', () {
    testWidgets('reports progress through to the state', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      final Future<void> work = controller.runTask<void>(
        (LoadingTask task) async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          task.report(0.5, detail: 'halfway');
          await Future<void>.delayed(const Duration(milliseconds: 150));
        },
        message: 'Uploading…',
        progress: 0,
      );

      await tester.pump(const Duration(milliseconds: 160));
      expect(controller.value.progress, 0.5);
      expect(controller.value.detail, 'halfway');

      await tester.pump(const Duration(milliseconds: 500));
      await work;
      controller.dispose();
    });

    testWidgets('offers cancel only after the grace period', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      final Future<void> expectation = expectLater(
        controller.runTask<void>(
          (LoadingTask task) async {
            for (var i = 0; i < 50; i++) {
              task.throwIfCancelled();
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          },
          message: 'Crunching…',
          cancelAfter: const Duration(milliseconds: 400),
        ),
        throwsA(isA<LoadingCancelled>()),
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.value.cancellable, isFalse,
          reason: 'too early to offer a way out');

      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.value.cancellable, isTrue);

      expect(controller.cancelTopmost(), isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      await expectation;
      expect(controller.isBusy, isFalse);
    });
  });

  group('teardown', () {
    testWidgets('dismissAll clears everything at once', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      controller.show(message: 'A');
      controller.show(message: 'B');
      await tester.pump(const Duration(milliseconds: 150));
      expect(controller.value.depth, 2);

      await controller.dismissAll(immediate: true);
      expect(controller.isBusy, isFalse);
      expect(controller.value, LoadingState.idle);
    });

    testWidgets('dismissOnNavigation: false survives a navigation clear', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      controller.show(message: 'transient');
      controller.show(message: 'persistent', dismissOnNavigation: false);
      await tester.pump(const Duration(milliseconds: 150));

      await controller.dismissAll(
        immediate: true,
        onlyNavigationScoped: true,
      );
      expect(controller.activeCount, 1);
      expect(controller.value.message, 'persistent');
      controller.dispose();
    });
  });
}
