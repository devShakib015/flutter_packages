// Records the README GIF from a REAL generation run.
//
// The usual `flutter test` frame recorder cannot be used here: it runs
// headless, and Apple refuses image creation to an app that is not frontmost.
// So the app records itself — it has to be foregrounded to generate anyway.
//
//   flutter build macos --debug -t lib/record.dart
//   open build/macos/Build/Products/Debug/apple_intelligence_example.app
//   ../tool/build_gifs.sh
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_intelligence/apple_intelligence.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

const String kOut = '/private/tmp/claude-501/-Users-devshakib-Projects/'
    '422a40fb-c07d-49d0-9ec0-e5bf2bdb790d/scratchpad/ai_frames';

final GlobalKey _stage = GlobalKey();

void main() => runApp(const Recorder());

class Recorder extends StatefulWidget {
  const Recorder({super.key});
  @override
  State<Recorder> createState() => _RecorderState();
}

class _RecorderState extends State<Recorder> {
  final List<GeneratedImage> _images = <GeneratedImage>[];
  final Stopwatch _clock = Stopwatch();
  String _caption = 'asking the device what it can do…';
  int _frame = 0;
  Timer? _ticker;
  bool _done = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    Directory(kOut)
      ..createSync(recursive: true)
      ..listSync().forEach((FileSystemEntity e) => e.deleteSync());
    unawaited(_run());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _log(String line) {
    File('$kOut/../ai_log.txt')
        .writeAsStringSync('$line\n', mode: FileMode.append);
  }

  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    final ImageGenerationAvailability a = await ImageCreator.availability();
    _log('availability status=${a.status.name} creator=${a.creator}');
    setState(
      () => _caption =
          'streaming ${a.creator ? "" : "un"}available · generating four images',
    );

    _clock.start();
    // One frame on the empty grid, so the GIF opens before anything lands.
    await _settleAndSnap();

    try {
      await for (final GeneratedImage image in ImageCreator.generate(
        concepts: <ImageConcept>[
          const ImageConcept.text('a fox reading a map by lantern light'),
        ],
        style: ImageStyle.illustration,
        limit: 4,
      )) {
        setState(() {
          _images.add(image);
          _caption = 'image ${_images.length} of 4 arrived at '
              '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
        });
        await _settleAndSnap();
      }
      setState(() {
        _done = true;
        _caption = 'all four in '
            '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s — '
            'each shown the moment it landed';
      });
      await _settleAndSnap();
    } catch (e) {
      _log('ERROR $e');
      setState(() => _caption = '$e');
    }
    _log(
      'finished with ${_images.length} image(s) in '
      '${_clock.elapsedMilliseconds}ms',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    _ticker?.cancel();
    stdout.writeln('RECORDED $_frame frames');
    exit(0);
  }

  /// Waits for the frame carrying the new state to be painted, then captures
  /// it. Capturing on an event rather than a timer is what makes this
  /// reliable: macOS throttles timers, and a stalled ticker silently truncates
  /// the recording part-way through the run.
  Future<void> _settleAndSnap() async {
    await WidgetsBinding.instance.endOfFrame;
    // Image.memory decodes asynchronously, so the frame after setState still
    // shows an empty cell. Give the decode a moment or the GIF captures the
    // border arriving without the picture inside it.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await WidgetsBinding.instance.endOfFrame;
    await _snap();
    await _snap(); // a second copy, so each step holds on screen in the GIF
    await _snap();
  }

  Future<void> _snap() async {
    // toImage gets expensive once multi-megabyte images are on screen. Without
    // a guard the ticks overlap, captures stall, and the recording silently
    // stops part-way through the run.
    if (_capturing) return;
    _capturing = true;
    final RenderObject? obj = _stage.currentContext?.findRenderObject();
    if (obj is! RenderRepaintBoundary) {
      _capturing = false;
      return;
    }
    try {
      final ui.Image img = await obj.toImage(pixelRatio: 1);
      final ByteData? png = await img.toByteData(
        format: ui.ImageByteFormat.png,
      );
      img.dispose();
      if (png == null) return;
      final String name = (_frame++).toString().padLeft(4, '0');
      File('$kOut/$name.png').writeAsBytesSync(png.buffer.asUint8List());
    } catch (_) {
      // A frame that cannot be captured is not worth stopping the run for.
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color bg = Color(0xFF0B0F17);
    const Color panel = Color(0xFF141A24);
    const Color text = Color(0xFFE6EDF3);
    const Color muted = Color(0xFF7D8590);
    const Color good = Color(0xFF34D399);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: _stage,
        child: Material(
          color: bg,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Text(
                      'apple_intelligence',
                      style: TextStyle(
                        color: text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _clock.isRunning || _done
                          ? '${(_clock.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'
                          : '',
                      style: const TextStyle(color: good, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _caption,
                  style: const TextStyle(color: muted, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: 4,
                    itemBuilder: (BuildContext c, int i) {
                      final bool has = i < _images.length;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: panel,
                          borderRadius: BorderRadius.circular(12),
                          border: has
                              ? Border.all(color: good.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: has
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _images[i].bytes,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: muted,
                                  ),
                                ),
                              ),
                      );
                    },
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
