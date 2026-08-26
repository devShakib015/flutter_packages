// Frame recorder for the README GIFs.
//
// Not a test — it is driven by `flutter test` only because that harness gives
// a rasterizer plus a fake clock. Rendering the demo this way means the GIF
// shows the package's real timing frame-accurately, rather than whatever a
// screen recorder happened to catch.
//
//   flutter test tool/record_frames.dart
//   ./tool/build_gifs.sh
//
// PNG frames land in doc/frames/<scene>/.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/loading_kit.dart';

/// 20fps — one frame per 50ms of simulated time.
const Duration kStep = Duration(milliseconds: 50);

/// Where frames are written, relative to the package root.
const String kOutDir = 'doc/frames';

final GlobalKey _stageKey = GlobalKey();

void main() {
  setUpAll(() async {
    final Uint8List bytes = File('tool/fonts/InterVariable.ttf')
        .readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');
  });

  testWidgets('scene: anti-flicker comparison', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('antiflicker');
    final LoadingController kit = LoadingController();
    final _NaiveController naive = _NaiveController();
    addTearDown(kit.dispose);
    addTearDown(naive.dispose);

    await tester.binding.setSurfaceSize(const Size(760, 470));
    await tester.pumpWidget(_ComparisonStage(kit: kit, naive: naive));
    await tester.pump(const Duration(milliseconds: 100));

    // Beat one: a request that comes back in 80ms.
    naive.caption = 'same 80 ms request';
    await rec.hold(tester, const Duration(milliseconds: 400));

    naive.busy = true;
    final LoadingHandle fast = kit.show(message: 'Loading…');
    await rec.hold(tester, const Duration(milliseconds: 80));
    naive.busy = false;
    unawaited(fast.dismiss());
    await rec.hold(tester, const Duration(milliseconds: 900));

    // Beat two: a request that genuinely takes a while.
    naive.caption = 'same 1.2 s request';
    await rec.hold(tester, const Duration(milliseconds: 400));

    naive.busy = true;
    final LoadingHandle slow = kit.show(message: 'Signing in…');
    await rec.hold(tester, const Duration(milliseconds: 1200));
    naive.busy = false;
    unawaited(slow.success('Welcome back'));
    await rec.hold(tester, const Duration(milliseconds: 1800));

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scene: preset gallery', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('presets');

    await tester.binding.setSurfaceSize(const Size(420, 460));
    for (final LoadingPreset preset in <LoadingPreset>[
      LoadingPreset.cupertino,
      LoadingPreset.material,
      LoadingPreset.glass,
      LoadingPreset.minimal,
      LoadingPreset.neon,
    ]) {
      final bool dark = preset == LoadingPreset.neon;
      final LoadingController controller = LoadingController(
        timing: LoadingTiming.instant,
      );

      await tester.pumpWidget(
        _PresetStage(controller: controller, preset: preset, dark: dark),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final LoadingHandle handle = controller.show(message: 'Uploading…');
      await rec.hold(tester, const Duration(milliseconds: 1100));
      unawaited(handle.success('Done'));
      await rec.hold(tester, const Duration(milliseconds: 900));

      controller.dispose();
    }
    rec.report();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scene: indicator styles', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('styles');

    await tester.binding.setSurfaceSize(const Size(560, 300));
    await tester.pumpWidget(const _StylesStage(status: LoadingStatus.busy));
    await rec.hold(tester, const Duration(milliseconds: 1700));
    await tester.pumpWidget(const _StylesStage(status: LoadingStatus.success));
    await rec.hold(tester, const Duration(milliseconds: 1100));

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scene: the morph', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('morph');

    await tester.binding.setSurfaceSize(const Size(420, 200));
    for (final LoadingStatus end in <LoadingStatus>[
      LoadingStatus.success,
      LoadingStatus.error,
    ]) {
      await tester.pumpWidget(_MorphStage(status: LoadingStatus.busy));
      await rec.hold(tester, const Duration(milliseconds: 1200));
      await tester.pumpWidget(_MorphStage(status: end));
      await rec.hold(tester, const Duration(milliseconds: 1000));
    }
    rec.report();
    await tester.binding.setSurfaceSize(null);
  });
}

/// Pumps in fixed steps and writes one PNG per step.
class _Recorder {
  _Recorder(this.scene) {
    dir = Directory('$kOutDir/$scene');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  }

  final String scene;
  late final Directory dir;
  int _index = 0;

  Future<void> hold(WidgetTester tester, Duration duration) async {
    final int steps = duration.inMilliseconds ~/ kStep.inMilliseconds;
    for (var i = 0; i < steps; i++) {
      await tester.pump(kStep);
      await _write(tester);
    }
  }

  Future<void> _write(WidgetTester tester) async {
    final String name = _index.toString().padLeft(4, '0');
    // runAsync escapes the fake clock: toImage resolves on the raster thread,
    // which never gets to run inside the test zone.
    await tester.runAsync(() async {
      final ui.Image image = await _captureStage(tester);
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (png == null) return;
      File('${dir.path}/$name.png').writeAsBytesSync(png.buffer.asUint8List());
    });
    _index++;
  }

  void report() {
    // ignore: avoid_print
    print('recorded $_index frames -> ${dir.path}');
  }
}

/// Rasterises the stage the same way `matchesGoldenFile` does.
Future<ui.Image> _captureStage(WidgetTester tester) {
  RenderObject? object = tester.renderObject(find.byKey(_stageKey));
  while (object != null && !object.isRepaintBoundary) {
    object = object.parent;
  }
  final OffsetLayer layer = object!.debugLayer! as OffsetLayer;
  return layer.toImage(object.paintBounds);
}

ThemeData _theme(bool dark) => ThemeData(
  colorSchemeSeed: const Color(0xFF4C6FFF),
  brightness: dark ? Brightness.dark : Brightness.light,
  fontFamily: 'Inter',
);

/// A stand-in app screen, so the overlay has something real to sit over.
class _FakeScreen extends StatelessWidget {
  const _FakeScreen({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < 3; i++) ...<Widget>[
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Spacer(),
            Container(
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'Sign in',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The naive overlay this package exists to replace: a bool and a Stack.
class _NaiveController extends ChangeNotifier {
  bool _busy = false;
  String _caption = '';

  bool get busy => _busy;
  set busy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  String get caption => _caption;
  set caption(String value) {
    if (_caption == value) return;
    _caption = value;
    notifyListeners();
  }
}

class _ComparisonStage extends StatelessWidget {
  const _ComparisonStage({required this.kit, required this.naive});

  final LoadingController kit;
  final _NaiveController naive;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(false),
      home: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: _stageKey,
          child: ColoredBox(
            color: const Color(0xFFE9ECF5),
            child: AnimatedBuilder(
              animation: naive,
              builder: (BuildContext context, Widget? _) {
                return Column(
                  children: <Widget>[
                    const SizedBox(height: 14),
                    Text(
                      naive.caption,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        children: <Widget>[
                          _Panel(
                            label: 'a bool and a Stack',
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                const _FakeScreen(title: 'Account'),
                                if (naive.busy)
                                  const ColoredBox(
                                    color: Color(0x66000000),
                                    child: Center(
                                      child: SizedBox.square(
                                        dimension: 34,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _Panel(
                            label: 'loading_kit',
                            highlight: true,
                            child: LoadingHost(
                              controller: kit,
                              registerGlobal: false,
                              style: LoadingStyle.material,
                              child: const _FakeScreen(title: 'Account'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.label,
    required this.child,
    this.highlight = false,
  });

  final String label;
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: highlight
                    ? const Color(0xFF4C6FFF)
                    : const Color(0xFF9AA3B2),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: highlight
                          ? const Color(0xFF4C6FFF).withValues(alpha: 0.45)
                          : const Color(0xFFD3D8E3),
                    ),
                  ),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetStage extends StatelessWidget {
  const _PresetStage({
    required this.controller,
    required this.preset,
    required this.dark,
  });

  final LoadingController controller;
  final LoadingPreset preset;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(dark),
      home: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: _stageKey,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              LoadingHost(
                controller: controller,
                registerGlobal: false,
                style: LoadingStyle(preset: preset),
                child: _FakeScreen(title: 'Account'),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      preset.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StylesStage extends StatelessWidget {
  const _StylesStage({required this.status});

  final LoadingStatus status;

  @override
  Widget build(BuildContext context) {
    const List<LoadingIndicatorStyle> styles = LoadingIndicatorStyle.values;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(false),
      home: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: _stageKey,
          child: ColoredBox(
            color: const Color(0xFFF4F6FB),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (int row = 0; row < 2; row++)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: <Widget>[
                        for (int col = 0; col < 3; col++)
                          _StyleCell(
                            style: styles[row * 3 + col],
                            status: status,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StyleCell extends StatelessWidget {
  const _StyleCell({required this.style, required this.status});

  final LoadingIndicatorStyle style;
  final LoadingStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox.square(
          dimension: 56,
          child: Center(
            child: LoadingIndicator(
              indicatorStyle: style,
              status: status,
              size: 46,
              strokeWidth: 4,
              style: LoadingStyle.material,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          style.name,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }
}

class _MorphStage extends StatelessWidget {
  const _MorphStage({required this.status});

  final LoadingStatus status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(false),
      home: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: _stageKey,
          child: ColoredBox(
            color: const Color(0xFFF4F6FB),
            child: Center(
              child: LoadingIndicator(
                status: status,
                size: 96,
                strokeWidth: 7,
                style: LoadingStyle.material,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
