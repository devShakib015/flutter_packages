// A player whose mini view pops out into a real floating window.
//
// The point of the demo is the shared state: `_Playback` sits ABOVE
// DocumentPipApp, so the page and the floating window are looking at the same
// object. Scrub in one and the other moves, because there is only one.
import 'package:document_pip/document_pip.dart';
import 'package:flutter/material.dart';

void main() => runWidget(buildApp());

/// The whole app, exposed so the smoke test can mount the same tree.
Widget buildApp() => _Playback(
      child: DocumentPipApp(
        main: (BuildContext context) => const _Shell(child: PageView2()),
        popOut: (BuildContext context) => const _Shell(child: MiniPlayer()),
      ),
    );

/// One clock, shared by every window.
class _Playback extends StatefulWidget {
  const _Playback({required this.child});
  final Widget child;

  static _PlaybackState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Scope>()!.state;

  @override
  State<_Playback> createState() => _PlaybackState();
}

class _PlaybackState extends State<_Playback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..addListener(() => setState(() {}));

  bool get playing => _c.isAnimating;
  double get progress => _c.value;

  void toggle() => playing ? _c.stop() : _c.repeat();
  void seek(double v) => _c.value = v;

  @override
  void initState() {
    super.initState();
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Scope(state: this, child: widget.child);
}

class _Scope extends InheritedWidget {
  const _Scope({required this.state, required super.child});
  final _PlaybackState state;

  @override
  bool updateShouldNotify(_Scope old) => true;
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF3DDC97),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: child,
      );
}

/// The page.
class PageView2 extends StatefulWidget {
  const PageView2({super.key});
  @override
  State<PageView2> createState() => _PageView2State();
}

class _PageView2State extends State<PageView2> {
  String _status = '';

  Future<void> _popOut() async {
    // First await in the handler, deliberately: anything before this spends
    // the user gesture and the browser refuses.
    try {
      final PipWindow w = await DocumentPip.open(width: 380, height: 210);
      setState(() => _status = 'floating in its own window');
      await w.closed;
      if (mounted) setState(() => _status = 'window closed');
    } on DocumentPipException catch (e) {
      if (mounted) setState(() => _status = e.message.split('\n').first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _PlaybackState p = _Playback.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'document_pip',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Pop the player out. It keeps running, above everything else.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              const _Scrubber(),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton.filledTonal(
                    onPressed: p.toggle,
                    iconSize: 30,
                    icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: DocumentPip.isSupported ? _popOut : null,
                    icon: const Icon(Icons.picture_in_picture_alt),
                    label: const Text('Pop out'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                DocumentPip.isSupported
                    ? _status
                    : 'This browser has no Document Picture-in-Picture — '
                        'Chrome or Edge is needed.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the floating window shows.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final _PlaybackState p = _Playback.of(context);
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Now playing', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'same widget tree, different window',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            const _Scrubber(),
            const SizedBox(height: 10),
            Align(
              child: IconButton.filledTonal(
                onPressed: p.toggle,
                icon: Icon(p.playing ? Icons.pause : Icons.play_arrow),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber();

  @override
  Widget build(BuildContext context) {
    final _PlaybackState p = _Playback.of(context);
    return Slider(value: p.progress, onChanged: p.seek);
  }
}
