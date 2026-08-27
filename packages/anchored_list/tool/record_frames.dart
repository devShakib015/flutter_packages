// Frame recorder for the README GIFs.
//
// Not a test — it is driven by `flutter test` only because that harness gives
// a rasterizer plus a fake clock. Recording the demo this way means the GIF
// shows real frames of the real widget, rather than whatever a screen
// recorder happened to catch.
//
//   flutter test tool/record_frames.dart
//   ./tool/build_gifs.sh
//
// PNG frames land in doc/frames/<scene>/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 20fps — one frame per 50ms of simulated time.
const Duration kStep = Duration(milliseconds: 50);

/// Where frames are written, relative to the package root.
const String kOutDir = 'doc/frames';

/// A million rows, so the numbers on screen are not a rounding error.
const int kRowCount = 1000000;

final GlobalKey _stageKey = GlobalKey();

// The readouts. These are the point of the first GIF: the index leaps by
// hundreds of thousands while the row count sits still.
int _rowsAlive = 0;
int _builderCalls = 0;

/// Bumped by the recorder before each capture so the header repaints in step
/// with the list. Mutating a notifier from a child's initState would fire
/// during build; driving it from outside the frame avoids that entirely.
final ValueNotifier<int> _tick = ValueNotifier<int>(0);
final ValueNotifier<String> _caption = ValueNotifier<String>('');

const Color _bg = Color(0xFF0B0F17);
const Color _panel = Color(0xFF141A24);
const Color _rowBg = Color(0xFF1B2330);
const Color _text = Color(0xFFE6EDF3);
const Color _muted = Color(0xFF7D8590);
const Color _accent = Color(0xFF7C9CFF);

void main() {
  setUpAll(() async {
    final Uint8List bytes = File('tool/fonts/InterVariable.ttf')
        .readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');
  });

  testWidgets('scene: jumping a million rows', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('jump');
    final AnchoredListController controller = AnchoredListController();
    addTearDown(controller.dispose);

    await tester.binding.setSurfaceSize(const Size(460, 420));
    _caption.value = 'a lazy list of one million rows';
    await tester.pumpWidget(_Stage(controller: controller));
    await tester.pump(const Duration(milliseconds: 100));
    await rec.hold(tester, const Duration(milliseconds: 800));

    // Each jump is a re-split of the viewport, not a walk down the list.
    for (final (int target, String note) in <(int, String)>[
      (250000, 'jumped 250,000 rows'),
      (617432, 'jumped 367,432 more'),
      (999999, 'the last row — nothing below it'),
      (3, 'and back to row 3'),
    ]) {
      controller.jumpToIndex(target);
      _caption.value = note;
      await rec.hold(tester, const Duration(milliseconds: 950));
    }

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('scene: scrolling either side of the anchor', (
    WidgetTester tester,
  ) async {
    final _Recorder rec = _Recorder('scroll');
    final AnchoredListController controller = AnchoredListController();
    addTearDown(controller.dispose);

    await tester.binding.setSurfaceSize(const Size(460, 420));
    _caption.value = 'opened at row 500,000';
    await tester.pumpWidget(
      _Stage(controller: controller, initialIndex: 500000),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await rec.hold(tester, const Duration(milliseconds: 700));

    // Dragging down walks backwards past the anchor, where the viewport is at
    // a negative scroll offset. It should feel like any other list.
    _caption.value = 'scrolling back past the anchor';
    await rec.drag(tester, const Offset(0, 260));
    await rec.hold(tester, const Duration(milliseconds: 600));

    _caption.value = 'and forward again';
    await rec.drag(tester, const Offset(0, -320));
    await rec.hold(tester, const Duration(milliseconds: 900));

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });
}

class _Stage extends StatelessWidget {
  const _Stage({required this.controller, this.initialIndex = 0});

  final AnchoredListController controller;
  final int initialIndex;

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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _Header(),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _panel,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AnchoredList.builder(
                        controller: controller,
                        initialIndex: initialIndex,
                        itemCount: kRowCount,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemBuilder: (BuildContext context, int index) {
                          _builderCalls++;
                          return _Row(index);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_tick, _caption]),
      builder: (BuildContext context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const Text(
                  'anchored_list',
                  style: TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                _Pill(label: 'rows alive', value: '$_rowsAlive'),
                const SizedBox(width: 8),
                _Pill(label: 'builder calls', value: '$_builderCalls'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _caption.value,
              style: const TextStyle(color: _muted, fontSize: 12.5),
            ),
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(color: _muted, fontSize: 10.5)),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              color: _accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Counts itself in and out so the header can show how few of these exist.
/// Note this is mount/unmount, not builds — Flutter recycles these elements,
/// so [_builderCalls] is the honest measure of work done.
class _Row extends StatefulWidget {
  const _Row(this.index);

  final int index;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    _rowsAlive++;
  }

  @override
  void dispose() {
    _rowsAlive--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              _fmt(widget.index),
              style: const TextStyle(
                color: _accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: <ui.FontFeature>[ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.05 + 0.05 * (widget.index % 3),
                ),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int n) {
  final String s = n.toString();
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
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

  /// A drag performed one recorded frame at a time, so the GIF shows the
  /// finger moving rather than jumping to the end of the gesture.
  Future<void> drag(
    WidgetTester tester,
    Offset total, {
    int frames = 14,
  }) async {
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(AnchoredList)),
    );
    final Offset per = total / frames.toDouble();
    for (int i = 0; i < frames; i++) {
      await gesture.moveBy(per);
      await tester.pump(kStep);
      await write(tester);
    }
    await gesture.up();
  }

  Future<void> write(WidgetTester tester) async {
    _tick.value++;
    await tester.pump(Duration.zero);
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

Future<ui.Image> _captureStage(WidgetTester tester) {
  RenderObject? object = tester.renderObject(find.byKey(_stageKey));
  while (object != null && !object.isRepaintBoundary) {
    object = object.parent;
  }
  final OffsetLayer layer = object!.debugLayer! as OffsetLayer;
  return layer.toImage(object.paintBounds, pixelRatio: 2);
}
