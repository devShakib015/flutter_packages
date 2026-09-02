// Frame recorder for the README GIF.
//
// Driven by `flutter test` because that harness gives a rasterizer plus a fake
// clock, so the recording is real frames of both packages rather than whatever
// a screen recorder happened to catch.
//
//   flutter test tool/record_frames.dart
//   ./tool/build_gifs.sh

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'
    as incumbent;
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_kit/masonry_kit.dart' as kit;

const Duration kStep = Duration(milliseconds: 50);
const String kOutDir = 'doc/frames';

final GlobalKey _stageKey = GlobalKey();
final ValueNotifier<int> _tick = ValueNotifier<int>(0);

const Color _bg = Color(0xFF0B0F17);
const Color _panel = Color(0xFF141A24);
const Color _text = Color(0xFFE6EDF3);
const Color _muted = Color(0xFF7D8590);
const Color _bad = Color(0xFFF87171);
const Color _good = Color(0xFF34D399);

double _h(int i) => 46.0 + (i * 37) % 74;

/// Watches one scroll view for the thing this package exists to prevent.
class _JumpWatch {
  _JumpWatch(this.controller) {
    controller.addListener(() {
      final double now = controller.offset;
      if (now < _highWater - 1) {
        final double back = _highWater - now;
        if (back > worst) worst = back;
        jumps++;
      }
      if (now > _highWater) _highWater = now;
    });
  }

  final ScrollController controller;
  double _highWater = 0;
  double worst = 0;
  int jumps = 0;
}

void main() {
  setUpAll(() async {
    final Uint8List bytes =
        File('tool/fonts/InterVariable.ttf').readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');
  });

  testWidgets('scene: two masonry grids in one scroll view', (
    WidgetTester tester,
  ) async {
    final _Recorder rec = _Recorder('jump');
    final ScrollController left = ScrollController();
    final ScrollController right = ScrollController();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final _JumpWatch lw = _JumpWatch(left);
    final _JumpWatch rw = _JumpWatch(right);

    await tester.binding.setSurfaceSize(const Size(560, 460));
    await tester.pumpWidget(_Stage(left: left, right: right, lw: lw, rw: rw));
    await tester.pump(const Duration(milliseconds: 100));
    await rec.hold(tester, const Duration(milliseconds: 500));

    // Both panels get the same finger, at the same time, for the same
    // distance. Anything that differs after this is the packages differing.
    final Offset leftCentre = tester.getCenter(find.byKey(const Key('left')));
    final Offset rightCentre = tester.getCenter(find.byKey(const Key('right')));
    final TestGesture gl = await tester.startGesture(leftCentre);
    final TestGesture gr = await tester.startGesture(rightCentre);
    for (int i = 0; i < 130; i++) {
      await gl.moveBy(const Offset(0, -34));
      await gr.moveBy(const Offset(0, -34));
      await tester.pump(kStep);
      await rec.write(tester);
    }
    await gl.up();
    await gr.up();
    await rec.hold(tester, const Duration(milliseconds: 700));

    rec.report();
    // ignore: avoid_print
    print(
      '  incumbent  : ${lw.jumps} jumps, worst ${lw.worst.toStringAsFixed(0)}px',
    );
    // ignore: avoid_print
    print(
      '  masonry_kit: ${rw.jumps} jumps, worst ${rw.worst.toStringAsFixed(0)}px',
    );
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scene: the layout itself', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('layout');
    final ScrollController scroll = ScrollController();
    addTearDown(scroll.dispose);

    _columns.value = 2;
    await tester.binding.setSurfaceSize(const Size(400, 440));
    await tester.pumpWidget(_LayoutStage(controller: scroll));
    await tester.pump(const Duration(milliseconds: 100));
    await rec.hold(tester, const Duration(milliseconds: 500));

    // Scroll a little, so it reads as a real lazy grid and not a picture.
    final TestGesture g = await tester.startGesture(
      tester.getCenter(find.byType(kit.MasonryGridView)),
    );
    for (int i = 0; i < 40; i++) {
      await g.moveBy(const Offset(0, -22));
      await tester.pump(kStep);
      await rec.write(tester);
    }
    await g.up();
    await rec.hold(tester, const Duration(milliseconds: 400));

    // Then reflow. Changing the column count is the one thing that genuinely
    // invalidates a placement, so the whole layout is recomputed from index 0.
    for (final int columns in <int>[3, 4, 2]) {
      _columns.value = columns;
      await rec.hold(tester, const Duration(milliseconds: 850));
    }

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });
}

final ValueNotifier<int> _columns = ValueNotifier<int>(2);

class _LayoutStage extends StatelessWidget {
  const _LayoutStage({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: RepaintBoundary(
        key: _stageKey,
        child: Material(
          color: _bg,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_tick, _columns]),
            builder: (BuildContext context, _) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Text(
                        'masonry_kit',
                        style: TextStyle(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'crossAxisCount: ${_columns.value}',
                        style: const TextStyle(color: _good, fontSize: 11.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kit.MasonryGridView.count(
                          controller: controller,
                          crossAxisCount: _columns.value,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          padding: const EdgeInsets.all(8),
                          itemCount: 200,
                          itemBuilder: (BuildContext c, int i) =>
                              _Tile(seed: 0, index: i),
                        ),
                      ),
                    ),
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

class _Stage extends StatelessWidget {
  const _Stage({
    required this.left,
    required this.right,
    required this.lw,
    required this.rw,
  });

  final ScrollController left;
  final ScrollController right;
  final _JumpWatch lw;
  final _JumpWatch rw;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: RepaintBoundary(
        key: _stageKey,
        child: Material(
          color: _bg,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: AnimatedBuilder(
              animation: _tick,
              builder: (BuildContext context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'two masonry grids in one CustomScrollView, same drag',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: _Panel(
                            title: 'flutter_staggered_grid_view',
                            watch: lw,
                            child: CustomScrollView(
                              key: const Key('left'),
                              controller: left,
                              slivers: <Widget>[
                                _incumbentGrid(0, 40),
                                _incumbentGrid(300, 40),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Panel(
                            title: 'masonry_kit',
                            watch: rw,
                            child: CustomScrollView(
                              key: const Key('right'),
                              controller: right,
                              slivers: <Widget>[
                                _kitGrid(0, 40),
                                _kitGrid(300, 40),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _incumbentGrid(int seed, int n) =>
      incumbent.SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childCount: n,
        itemBuilder: (BuildContext c, int i) => _Tile(seed: seed, index: i),
      );

  static Widget _kitGrid(int seed, int n) => kit.SliverMasonryGrid.count(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childCount: n,
        itemBuilder: (BuildContext c, int i) => _Tile(seed: seed, index: i),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.watch, required this.child});

  final String title;
  final _JumpWatch watch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool broken = watch.jumps > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            color: broken ? _bad : _good,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          broken
              ? 'jumped back ${watch.worst.toStringAsFixed(0)}px'
              : 'no backward jumps',
          style: TextStyle(
            color: broken ? _bad : _muted,
            fontSize: 10,
            fontWeight: broken ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.seed, required this.index});

  final int seed;
  final int index;

  @override
  Widget build(BuildContext context) {
    final int n = seed + index;
    return Container(
      height: _h(n),
      margin: const EdgeInsets.all(3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.lerp(
          const Color(0xFF1B2330),
          const Color(0xFF2D3A52),
          (n % 7) / 7,
        ),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '${seed == 0 ? "a" : "b"}$index',
        style: const TextStyle(color: _text, fontSize: 11),
      ),
    );
  }
}

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
    for (int i = 0; i < steps; i++) {
      await tester.pump(kStep);
      await write(tester);
    }
  }

  Future<void> write(WidgetTester tester) async {
    _tick.value++;
    await tester.pump(Duration.zero);
    final String name = _index.toString().padLeft(4, '0');
    await tester.runAsync(() async {
      final ui.Image image = await _capture(tester);
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

Future<ui.Image> _capture(WidgetTester tester) {
  RenderObject? object = tester.renderObject(find.byKey(_stageKey));
  while (object != null && !object.isRepaintBoundary) {
    object = object.parent;
  }
  final OffsetLayer layer = object!.debugLayer! as OffsetLayer;
  return layer.toImage(object.paintBounds, pixelRatio: 2);
}
