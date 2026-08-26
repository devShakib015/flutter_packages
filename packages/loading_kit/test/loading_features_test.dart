import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

void main() {
  const LoadingTiming timing = LoadingTiming(
    delay: Duration(milliseconds: 100),
    minVisible: Duration(milliseconds: 200),
  );

  LoadingController build() {
    final LoadingController controller = LoadingController(timing: timing);
    addTearDown(controller.dispose);
    return controller;
  }

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

  group('toasts', () {
    testWidgets('appear without a scrim and leave on their own', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      await tester.pumpWidget(host(controller));

      controller.toast('Draft saved', duration: const Duration(seconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Draft saved'), findsOneWidget);
      expect(
        find.byType(LoadingCard),
        findsNothing,
        reason: 'a toast is not a blocking overlay',
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Draft saved'), findsNothing);
    });

    testWidgets('never intercept input', (WidgetTester tester) async {
      final LoadingController controller = build();
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          builder: LoadingKit.builder(
            controller: controller,
            registerGlobal: false,
            toastAlignment: Alignment.center,
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

      controller.toast('Over the button', duration: const Duration(days: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Over the button'), findsOneWidget);

      await tester.tap(find.text('Tap me'));
      expect(taps, 1, reason: 'the toast layer must stay pointer-transparent');

      controller.clearToasts();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a burst retires the oldest instead of filling the screen', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      await tester.pumpWidget(host(controller));

      for (var i = 1; i <= 5; i++) {
        controller.toast('Toast $i', duration: const Duration(days: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Toast 1'), findsNothing);
      expect(find.text('Toast 2'), findsNothing);
      expect(find.text('Toast 5'), findsOneWidget);

      controller.clearToasts();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('custom indicator', () {
    testWidgets('indicatorBuilder replaces the built-in form', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      await tester.pumpWidget(
        host(
          controller,
          style: LoadingStyle.material.copyWith(
            indicatorBuilder: (BuildContext context, LoadingIndicatorSpec s) =>
                SizedBox.square(
                  dimension: s.size,
                  child: ColoredBox(
                    color: s.statusColor,
                    child: const Text('mine'),
                  ),
                ),
          ),
        ),
      );

      controller.show(message: 'Working…');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('mine'), findsOneWidget);
      expect(
        find.byType(LoadingIndicator),
        findsNothing,
        reason: 'the builder owns the whole slot',
      );

      await controller.dismissAll(immediate: true);
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('progress bar', () {
    testWidgets('bar style renders a bar while busy, a glyph when settled', (
      WidgetTester tester,
    ) async {
      final LoadingController controller = build();
      await tester.pumpWidget(
        host(
          controller,
          style: LoadingStyle.material.copyWith(
            progressStyle: LoadingProgressStyle.bar,
          ),
        ),
      );

      final LoadingHandle handle = controller.show(
        message: 'Uploading…',
        progress: 0.4,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(LoadingProgressBar), findsOneWidget);

      unawaited(handle.success('Done'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(LoadingIndicator),
        findsWidgets,
        reason: 'the outcome is still the glyph',
      );

      await controller.dismissAll(immediate: true);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('LoadingBarrier', () {
    testWidgets('honours the reveal delay like the full-screen host', (
      WidgetTester tester,
    ) async {
      Widget app({required bool loading}) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 200,
              child: LoadingBarrier(
                loading: loading,
                message: 'Saving…',
                timing: timing,
                child: const Center(child: Text('form')),
              ),
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(loading: false));
      expect(find.byType(LoadingCard), findsNothing);

      await tester.pumpWidget(app(loading: true));
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        find.byType(LoadingCard),
        findsNothing,
        reason: 'still inside the reveal delay',
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        find.text('form'),
        findsOneWidget,
        reason: 'the barrier covers the subtree, it does not replace it',
      );

      await tester.pumpWidget(app(loading: false));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LoadingCard), findsNothing);
    });

    testWidgets('a fast operation inside a barrier paints nothing', (
      WidgetTester tester,
    ) async {
      Widget app({required bool loading}) => MaterialApp(
        home: Scaffold(
          body: LoadingBarrier(
            loading: loading,
            timing: timing,
            child: const Center(child: Text('form')),
          ),
        ),
      );

      await tester.pumpWidget(app(loading: false));
      await tester.pumpWidget(app(loading: true));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(app(loading: false));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(LoadingCard), findsNothing);
    });
  });

  group('indicator styles', () {
    testWidgets('every style renders and animates', (
      WidgetTester tester,
    ) async {
      for (final LoadingIndicatorStyle style in LoadingIndicatorStyle.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: Center(child: LoadingIndicator(indicatorStyle: style)),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(
          find.byType(LoadingIndicator),
          findsOneWidget,
          reason: '${style.name} should render',
        );
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
