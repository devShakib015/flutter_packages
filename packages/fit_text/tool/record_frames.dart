// Frame recorder for the README GIF.
//
//   flutter test tool/record_frames.dart
//   ./tool/build_gifs.sh

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fit_text/fit_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Duration kStep = Duration(milliseconds: 50);
const String kOut = 'doc/frames';
final GlobalKey _stage = GlobalKey();
final ValueNotifier<double> _width = ValueNotifier<double>(460);

const Color _bg = Color(0xFF0B0F17);
const Color _panel = Color(0xFF141A24);
const Color _text = Color(0xFFE6EDF3);
const Color _muted = Color(0xFF7D8590);
const Color _good = Color(0xFF34D399);
const Color _bad = Color(0xFFF87171);

const String _line = 'The quick brown fox jumps over the lazy dog';

void main() {
  setUpAll(() async {
    final Uint8List bytes = File('tool/fonts/InterVariable.ttf')
        .readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');
  });

  testWidgets('scene: fitting as the box narrows', (WidgetTester tester) async {
    final _Recorder rec = _Recorder('fitting');
    await tester.binding.setSurfaceSize(const Size(520, 300));
    _width.value = 460;
    await tester.pumpWidget(const _Stage());
    await tester.pump(const Duration(milliseconds: 100));
    await rec.hold(tester, const Duration(milliseconds: 400));

    // Narrow, then widen again. The same string, one line, never wrapping.
    for (final (double from, double to) in <(double, double)>[
      (460, 150),
      (150, 460),
    ]) {
      const int steps = 36;
      for (int i = 0; i <= steps; i++) {
        _width.value = from + (to - from) * (i / steps);
        await tester.pump(kStep);
        await rec.write(tester);
      }
      await rec.hold(tester, const Duration(milliseconds: 300));
    }

    rec.report();
    await tester.binding.setSurfaceSize(null);
  });
}

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: RepaintBoundary(
        key: _stage,
        child: Material(
          color: _bg,
          child: AnimatedBuilder(
            animation: _width,
            builder: (BuildContext context, _) => Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'one line, ${_width.value.toStringAsFixed(0)}px wide',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  _Row(
                    label: 'FitText',
                    good: true,
                    child: FitText(
                      _line,
                      maxLines: 1,
                      minFontSize: 6,
                      style: const TextStyle(color: _text, fontSize: 26),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Row(
                    label: 'Text',
                    good: false,
                    child: const Text(
                      _line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _muted, fontSize: 26),
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.good, required this.child});

  final String label;
  final bool good;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: good ? _good : _bad,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          width: _width.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _Recorder {
  _Recorder(this.scene) {
    dir = Directory('$kOut/$scene');
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
    final String name = _index.toString().padLeft(4, '0');
    await tester.runAsync(() async {
      RenderObject? obj = tester.renderObject(find.byKey(_stage));
      while (obj != null && !obj.isRepaintBoundary) {
        obj = obj.parent;
      }
      final ui.Image image = await (obj! as RenderRepaintBoundary).toImage(
        pixelRatio: 2,
      );
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (png != null) {
        File('${dir.path}/$name.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });
    _index++;
  }

  void report() {
    // ignore: avoid_print
    print('recorded $_index frames -> ${dir.path}');
  }
}
