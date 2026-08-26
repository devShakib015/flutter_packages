// Renders the README GIFs by replaying a real captured session.
//
// tool/capture.json holds snapshots and millisecond timings recorded from an
// actual run of the on-device model (see the Swift capture in the repo notes).
// Replaying them here means the GIFs show text the model really produced, at
// the speed it really produced it — including the first-token latency, which
// is worth seeing rather than hiding.
//
//   flutter test tool/record_frames.dart
//   ./tool/build_gifs.sh

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 20fps.
const Duration kStep = Duration(milliseconds: 50);

/// Where frames are written, relative to the package root.
const String kOutDir = 'doc/frames';

final GlobalKey _stageKey = GlobalKey();

/// One captured snapshot: the whole response at [t] milliseconds.
class Frame {
  /// Creates a snapshot.
  Frame(this.t, this.s);

  /// Milliseconds since the request started.
  final int t;

  /// The complete response so far.
  final String s;
}

/// A captured scene.
class Scene {
  /// Creates a scene.
  Scene(this.prompt, this.frames, {this.toolArgs, this.toolResult});

  /// What was asked.
  final String prompt;

  /// Snapshots in order.
  final List<Frame> frames;

  /// Arguments the model passed to the tool, when this scene used one.
  final String? toolArgs;

  /// What the tool returned.
  final String? toolResult;

  /// Total captured duration.
  int get duration => frames.isEmpty ? 0 : frames.last.t;

  /// The snapshot visible at [ms], or null before the first one arrives.
  String? at(int ms) {
    String? current;
    for (final Frame f in frames) {
      if (f.t <= ms) current = f.s;
    }
    return current;
  }

  /// Reads a scene out of the capture file.
  static Scene fromJson(Map<String, dynamic> json) => Scene(
    json['prompt'] as String,
    <Frame>[
      for (final dynamic f in json['frames'] as List<dynamic>)
        Frame((f as Map<String, dynamic>)['t'] as int, f['s'] as String),
    ],
    toolArgs: json['toolArgs'] as String?,
    toolResult: json['toolResult'] as String?,
  );
}

void main() {
  late Map<String, Scene> scenes;

  setUpAll(() async {
    final Uint8List bytes = File('tool/fonts/InterVariable.ttf')
        .readAsBytesSync();
    await ui.loadFontFromList(bytes, fontFamily: 'Inter');

    final Map<String, dynamic> raw = jsonDecode(
      File('tool/capture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    scenes = <String, Scene>{
      for (final MapEntry<String, dynamic> e in raw.entries)
        e.key: Scene.fromJson(e.value as Map<String, dynamic>),
    };
  });

  testWidgets('scene: streaming text', (WidgetTester tester) async {
    final Scene scene = scenes['text']!;
    await _record(tester, 'stream', scene.duration + 900, (int ms) {
      return _Stage(
        title: 'session.stream(...)',
        prompt: scene.prompt,
        elapsedMs: ms,
        totalMs: scene.duration,
        body: _Prose(text: scene.at(ms)),
      );
    });
  });

  testWidgets('scene: structured output', (WidgetTester tester) async {
    final Scene scene = scenes['structured']!;
    await _record(tester, 'structured', scene.duration + 1400, (int ms) {
      return _Stage(
        title: 'session.streamAs(..., schema: triage)',
        prompt: scene.prompt,
        elapsedMs: ms,
        totalMs: scene.duration,
        body: _Fields(json: scene.at(ms)),
      );
    });
  });

  testWidgets('scene: tool calling', (WidgetTester tester) async {
    final Scene scene = scenes['tool']!;
    // The tool ran before the first snapshot; show it landing part way in.
    const int toolAt = 260;
    await _record(tester, 'tool', scene.duration + 1200, (int ms) {
      return _Stage(
        title: 'the model calls your Dart function',
        prompt: scene.prompt,
        elapsedMs: ms,
        totalMs: scene.duration,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (ms >= toolAt)
              _ToolCard(args: scene.toolArgs!, result: scene.toolResult!),
            if (ms >= toolAt) const SizedBox(height: 14),
            _Prose(text: scene.at(ms)),
          ],
        ),
      );
    });
  });
}

Future<void> _record(
  WidgetTester tester,
  String name,
  int totalMs,
  Widget Function(int ms) build,
) async {
  final Directory dir = Directory('$kOutDir/$name');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);

  await tester.binding.setSurfaceSize(const Size(720, 400));
  var index = 0;
  for (var ms = 0; ms <= totalMs; ms += kStep.inMilliseconds) {
    await tester.pumpWidget(build(ms));
    await tester.pump(kStep);
    await tester.runAsync(() async {
      RenderObject? object = tester.renderObject(find.byKey(_stageKey));
      while (object != null && !object.isRepaintBoundary) {
        object = object.parent;
      }
      final ui.Image image = await (object!.debugLayer! as OffsetLayer).toImage(
        object.paintBounds,
      );
      final ByteData? png = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (png != null) {
        File('${dir.path}/${index.toString().padLeft(4, '0')}.png')
            .writeAsBytesSync(png.buffer.asUint8List());
      }
    });
    index++;
  }
  // ignore: avoid_print
  print('recorded $index frames -> ${dir.path}');
  await tester.binding.setSurfaceSize(null);
}

const Color _kInk = Color(0xFF11151C);
const Color _kMuted = Color(0xFF6B7280);
const Color _kAccent = Color(0xFF6B5BFF);

class _Stage extends StatelessWidget {
  const _Stage({
    required this.title,
    required this.prompt,
    required this.elapsedMs,
    required this.totalMs,
    required this.body,
  });

  final String title;
  final String prompt;
  final int elapsedMs;
  final int totalMs;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final bool finished = elapsedMs >= totalMs;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Inter', useMaterial3: true),
      home: Material(
        type: MaterialType.transparency,
        child: RepaintBoundary(
          key: _stageKey,
          child: ColoredBox(
            color: const Color(0xFFF5F6FA),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: _kAccent,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: finished
                              ? const Color(0xFF2FA96B).withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          finished
                              ? 'done in ${(totalMs / 1000).toStringAsFixed(2)}s'
                              : '${(elapsedMs / 1000).toStringAsFixed(2)}s',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: finished ? const Color(0xFF2FA96B) : _kMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E5EE)),
                    ),
                    child: Text(
                      prompt,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: _kInk,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: body),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose({required this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const _Waiting();
    return Text(
      text!,
      style: const TextStyle(fontSize: 15.5, height: 1.5, color: _kInk),
    );
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < 3; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: _kMuted.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 6),
        const Text(
          'generating on device',
          style: TextStyle(fontSize: 13, color: _kMuted),
        ),
      ],
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.json});

  final String? json;

  @override
  Widget build(BuildContext context) {
    if (json == null) return const _Waiting();
    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(json!) as Map<String, dynamic>;
    } catch (_) {
      return const _Waiting();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final String key in <String>['priority', 'summary', 'tags'])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 86,
                  child: Text(
                    key,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kMuted,
                    ),
                  ),
                ),
                Expanded(child: _Value(value: parsed[key])),
              ],
            ),
          ),
      ],
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({required this.value});

  final Object? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || (value is String && (value! as String).isEmpty)) {
      return Container(
        height: 14,
        width: 120,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E5EE),
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    if (value is List) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final Object? v in value! as List<Object?>)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$v',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _kAccent,
                ),
              ),
            ),
        ],
      );
    }
    return Text(
      '$value',
      style: const TextStyle(fontSize: 14.5, height: 1.35, color: _kInk),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.args, required this.result});

  final String args;
  final String result;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kAccent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'your Dart handler ran',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: _kAccent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'getWeather($args)',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '→ "$result"',
            style: const TextStyle(fontSize: 13.5, color: _kMuted),
          ),
        ],
      ),
    );
  }
}
