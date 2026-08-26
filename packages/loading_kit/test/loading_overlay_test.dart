import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

void main() {
  const LoadingTiming timing = LoadingTiming(
    delay: Duration(milliseconds: 100),
    minVisible: Duration(milliseconds: 200),
    successHold: Duration(milliseconds: 200),
    errorHold: Duration(milliseconds: 200),
  );

  Widget host(LoadingController controller, {LoadingStyle? style}) {
    return MaterialApp(
      builder: LoadingKit.builder(
        controller: controller,
        style: style ?? LoadingStyle.material,
        registerGlobal: false,
      ),
      home: const Scaffold(body: Center(child: Text('app body'))),
    );
  }

  LoadingController build() {
    final LoadingController controller = LoadingController(timing: timing);
    addTearDown(controller.dispose);
    return controller;
  }

  testWidgets('nothing is built while idle', (WidgetTester tester) async {
    final LoadingController controller = build();
    await tester.pumpWidget(host(controller));

    expect(find.byType(LoadingCard), findsNothing);
    expect(find.byType(LoadingIndicator), findsNothing);
    expect(find.text('app body'), findsOneWidget);
  });

  testWidgets('the card appears with its message and then leaves', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    await tester.pumpWidget(host(controller));

    final LoadingHandle handle = controller.show(message: 'Signing in…');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(LoadingCard), findsOneWidget);
    expect(find.text('Signing in…'), findsOneWidget);

    final Future<void> closed = handle.dismiss();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoadingCard), findsNothing);
    await closed;
  });

  testWidgets('a fast operation never builds a card', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    await tester.pumpWidget(host(controller));

    final Future<void> work = controller.run(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
      message: 'Should never appear',
    );

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byType(LoadingCard), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await work;
    expect(find.text('Should never appear'), findsNothing);
  });

  testWidgets('the scrim swallows taps meant for the app', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(
          controller: controller,
          registerGlobal: false,
        ),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => taps++,
              child: const Text('Tap me'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tap me'));
    expect(taps, 1, reason: 'reachable before the overlay');

    controller.show(message: 'Busy');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Tap me'), warnIfMissed: false);
    expect(taps, 1, reason: 'the scrim blocks the button underneath');

    await controller.dismissAll(immediate: true);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the app behind is removed from focus traversal while busy', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: LoadingKit.builder(
          controller: controller,
          registerGlobal: false,
        ),
        home: Scaffold(
          body: Center(
            child: TextField(focusNode: node),
          ),
        ),
      ),
    );

    node.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue);

    controller.show(message: 'Busy');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    expect(node.hasFocus, isFalse,
        reason: 'focus must not sit under a blocking scrim');

    await controller.dismissAll(immediate: true);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the overlay announces itself to screen readers', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final LoadingController controller = build();
    await tester.pumpWidget(host(controller));

    controller.show(message: 'Uploading…', progress: 0.5);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));

    final SemanticsNode node =
        tester.getSemantics(find.byType(LoadingOverlay));
    expect(node.label, 'Uploading…',
        reason: 'announced exactly once, not doubled by the container label');
    expect(node.value, '50%', reason: 'progress is announced, not just shown');
    expect(
      find.descendant(
        of: find.byType(LoadingOverlay),
        matching: find.byType(BlockSemantics),
      ),
      findsOneWidget,
      reason: 'the blocked app must be hidden from the screen reader too',
    );

    await controller.dismissAll(immediate: true);
    await tester.pump(const Duration(milliseconds: 400));
    semantics.dispose();
  });

  testWidgets('a route change clears an overlay left behind', (
    WidgetTester tester,
  ) async {
    final LoadingController controller = build();
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: <NavigatorObserver>[
          LoadingNavigatorObserver(controller: controller),
        ],
        builder: LoadingKit.builder(
          controller: controller,
          registerGlobal: false,
        ),
        home: const Scaffold(body: Text('first')),
      ),
    );

    controller.show(message: 'Stuck?');
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoadingCard), findsOneWidget);

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => const Scaffold(body: Text('second')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LoadingCard), findsNothing,
        reason: 'an overlay must not outlive the screen that started it');
    expect(controller.isBusy, isFalse);
  });
}
