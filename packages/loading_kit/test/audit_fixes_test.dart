// Each test pins a defect found by the 2026-09-02 audit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

void main() {
  testWidgets('a nested host handing back does not kill the global facade', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.3.1: Loading held a single controller, so a nested
    // LoadingHost replaced the root on mount and set the facade to NULL on
    // unmount. Every later Loading.show() in the app then threw
    // LoadingHostMissing even though the root host was still mounted — one
    // modal with its own host poisoned the whole app.
    late StateSetter setOuter;
    bool nested = false;

    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(),
        home: StatefulBuilder(
          builder: (BuildContext ctx, StateSetter set) {
            setOuter = set;
            const Widget body = Scaffold(body: Text('root'));
            return nested ? const LoadingHost(child: body) : body;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(Loading.isInstalled, isTrue);

    setOuter(() => nested = true);
    await tester.pumpAndSettle();
    expect(Loading.isInstalled, isTrue);

    setOuter(() => nested = false);
    await tester.pumpAndSettle();

    expect(
      Loading.isInstalled,
      isTrue,
      reason: 'the root host is still mounted and must get the facade back',
    );
    expect(() => Loading.instance, returnsNormally);
  });

  testWidgets('show(dismissible: true) can actually be dismissed', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.3.1: the flag rendered a tap target, but the scrim calls
    // cancelTopmost() which looks for an operation carrying an onCancel — and
    // only run()/runTask() ever set one. A plain show() had none, so the tap
    // did nothing, or found an unrelated operation lower in the stack and
    // cancelled that instead.
    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(),
        home: const Scaffold(body: Text('root')),
      ),
    );
    await tester.pumpAndSettle();

    final LoadingController controller = Loading.instance;
    controller.show(message: 'Working', dismissible: true);
    await tester.pumpAndSettle();
    expect(controller.isBusy, isTrue);

    expect(
      controller.cancelTopmost(),
      isTrue,
      reason: 'a dismissible operation must be cancellable',
    );
    await tester.pumpAndSettle();
    expect(controller.isBusy, isFalse);
  });

  testWidgets('show(dismissible: false) is still not cancellable', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(),
        home: const Scaffold(body: Text('root')),
      ),
    );
    await tester.pumpAndSettle();

    final LoadingController controller = Loading.instance;
    controller.show(message: 'Working');
    await tester.pumpAndSettle();

    expect(controller.cancelTopmost(), isFalse);
    expect(controller.isBusy, isTrue);
    await controller.dismissAll(immediate: true);
    await tester.pumpAndSettle();
  });

  testWidgets('a push while loading does not crash under the pages API', (
    WidgetTester tester,
  ) async {
    // Shipped in 0.3.1: the observer cleared synchronously inside didPush,
    // which under the pages API happens during the build phase — and
    // dismissAll mutates a ValueNotifier the overlay listens to. That is
    // "setState() called during build".
    final List<Page<void>> pages = <Page<void>>[
      const MaterialPage<void>(child: Scaffold(body: Text('one'))),
    ];
    late StateSetter setOuter;

    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(),
        home: StatefulBuilder(
          builder: (BuildContext ctx, StateSetter set) {
            setOuter = set;
            return Navigator(
              pages: List<Page<void>>.of(pages),
              observers: <NavigatorObserver>[LoadingNavigatorObserver()],
              onDidRemovePage: (Page<void> p) => pages.remove(p),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    Loading.instance.show(message: 'Working');
    await tester.pumpAndSettle();

    setOuter(
      () => pages.add(
        const MaterialPage<void>(child: Scaffold(body: Text('two'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(Loading.isBusy, isFalse, reason: 'the push still clears it');
  });
}
