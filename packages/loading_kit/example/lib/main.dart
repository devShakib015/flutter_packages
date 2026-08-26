import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loading_kit/loading_kit.dart';

void main() => runApp(const GalleryApp());

/// Demo app cycling every preset through every behaviour the package has.
class GalleryApp extends StatefulWidget {
  /// Creates the gallery.
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  LoadingPreset _preset = LoadingPreset.adaptive;
  ThemeMode _mode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'loading_kit',
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4C6FFF),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4C6FFF),
        brightness: Brightness.dark,
      ),
      navigatorObservers: <NavigatorObserver>[LoadingNavigatorObserver()],
      builder: LoadingKit.builder(style: LoadingStyle(preset: _preset)),
      home: GalleryPage(
        preset: _preset,
        mode: _mode,
        onPreset: (LoadingPreset p) => setState(() => _preset = p),
        onMode: (ThemeMode m) => setState(() => _mode = m),
      ),
    );
  }
}

/// The gallery's single screen.
class GalleryPage extends StatelessWidget {
  /// Creates the gallery page.
  const GalleryPage({
    super.key,
    required this.preset,
    required this.mode,
    required this.onPreset,
    required this.onMode,
  });

  /// Currently selected preset.
  final LoadingPreset preset;

  /// Currently selected theme mode.
  final ThemeMode mode;

  /// Called when the preset changes.
  final ValueChanged<LoadingPreset> onPreset;

  /// Called when the theme mode changes.
  final ValueChanged<ThemeMode> onMode;

  static Future<void> _wait(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('loading_kit'),
        actions: <Widget>[
          IconButton(
            tooltip: dark ? 'Light theme' : 'Dark theme',
            icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => onMode(dark ? ThemeMode.light : ThemeMode.dark),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const _SectionTitle('Preset'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LoadingPreset.values.map((LoadingPreset p) {
              return ChoiceChip(
                label: Text(p.name),
                selected: p == preset,
                onSelected: (_) => onPreset(p),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const _SectionTitle('The anti-flicker guarantee'),
          _Tile(
            title: 'Fast operation — 80ms',
            subtitle:
                'Resolves inside the reveal delay, so nothing paints at '
                'all. This is the whole point.',
            onTap: () => Loading.run(() => _wait(80)),
          ),
          _Tile(
            title: 'Borderline operation — 200ms',
            subtitle:
                'Crosses the delay, so it paints — and is then held for '
                'the minimum window instead of blinking out.',
            onTap: () => Loading.run(() => _wait(200)),
          ),
          const _SectionTitle('Everyday'),
          _Tile(
            title: 'Plain load',
            subtitle: 'Message only, dismissed silently.',
            onTap: () => Loading.run(() => _wait(1600), message: 'Loading…'),
          ),
          _Tile(
            title: 'Success feedback',
            subtitle: 'The arc closes into a check without swapping widgets.',
            onTap: () => Loading.run(
              () => _wait(1400),
              message: 'Signing in…',
              successMessage: 'Welcome back',
            ),
          ),
          _Tile(
            title: 'Error feedback',
            subtitle:
                'Same arc, settling into a cross. The throw still '
                'propagates to your catch block.',
            onTap: () async {
              try {
                await Loading.run<void>(
                  () async {
                    await _wait(1200);
                    throw StateError('offline');
                  },
                  message: 'Syncing…',
                  errorMessage: 'Could not reach the server',
                );
              } on StateError {
                // Swallowed: the overlay already reported it.
              }
            },
          ),
          const _SectionTitle('Progress and cancellation'),
          _Tile(
            title: 'Determinate upload',
            subtitle:
                'Coarse progress jumps are interpolated into continuous '
                'motion.',
            onTap: () => Loading.runTask<void>(
              (LoadingTask task) async {
                for (var i = 1; i <= 5; i++) {
                  await _wait(420);
                  task.report(i / 5, detail: '$i of 5 files');
                }
              },
              message: 'Uploading…',
              progress: 0,
              successMessage: 'Uploaded',
            ),
          ),
          _Tile(
            title: 'Cancellable job',
            subtitle:
                'The cancel affordance appears after 1.5s, so quick runs '
                'never offer one.',
            onTap: () async {
              final ScaffoldMessengerState messenger = ScaffoldMessenger.of(
                context,
              );
              try {
                await Loading.runTask<void>(
                  (LoadingTask task) async {
                    for (var i = 0; i < 20; i++) {
                      task.throwIfCancelled();
                      await _wait(300);
                    }
                  },
                  message: 'Crunching numbers…',
                  detail: 'This one takes a while',
                  cancelAfter: const Duration(milliseconds: 1500),
                );
              } on LoadingCancelled {
                messenger
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('Cancelled')));
              }
            },
          ),
          _Tile(
            title: 'Timeout',
            subtitle: 'Fails after 2s rather than hanging forever.',
            onTap: () async {
              try {
                await Loading.run(
                  () => _wait(10000),
                  message: 'Connecting…',
                  timeout: const Duration(seconds: 2),
                  errorMessage: 'Timed out',
                );
              } on TimeoutException {
                // Reported by the overlay.
              }
            },
          ),
          const _SectionTitle('Correctness'),
          _Tile(
            title: 'Three concurrent requests',
            subtitle:
                'Reference counted — the overlay stays until the last '
                'one finishes, not the first.',
            onTap: () async {
              await Future.wait<void>(<Future<void>>[
                Loading.run(() => _wait(900), message: 'Request A'),
                Loading.run(() => _wait(1800), message: 'Request B'),
                Loading.run(() => _wait(2700), message: 'Request C'),
              ]);
            },
          ),
          _Tile(
            title: 'Overlay survives a dialog',
            subtitle: 'Opens a dialog, then loads on top of it.',
            onTap: () async {
              unawaited(
                showDialog<void>(
                  context: context,
                  builder: (BuildContext c) => AlertDialog(
                    title: const Text('A dialog'),
                    content: const Text(
                      'The overlay paints above this, because the host sits '
                      'above the navigator.',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              );
              await _wait(400);
              await Loading.run(() => _wait(1800), message: 'Loading…');
            },
          ),
          _Tile(
            title: 'Manual handle',
            subtitle: 'Drive message, detail and progress by hand.',
            onTap: () async {
              final LoadingHandle handle = Loading.show(message: 'Preparing…');
              await _wait(700);
              handle.update(message: 'Compressing…', progress: 0.2);
              await _wait(700);
              handle.update(detail: 'almost there', progress: 0.85);
              await _wait(700);
              await handle.success('Done');
            },
          ),
          const _SectionTitle('The indicator on its own'),
          const _IndicatorRow(),
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatefulWidget {
  const _IndicatorRow();

  @override
  State<_IndicatorRow> createState() => _IndicatorRowState();
}

class _IndicatorRowState extends State<_IndicatorRow> {
  double _progress = 0.35;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                const _Labelled('busy', LoadingIndicator(size: 44)),
                _Labelled(
                  'progress',
                  LoadingIndicator(size: 44, progress: _progress),
                ),
                const _Labelled(
                  'success',
                  LoadingIndicator(size: 44, status: LoadingStatus.success),
                ),
                const _Labelled(
                  'error',
                  LoadingIndicator(size: 44, status: LoadingStatus.error),
                ),
              ],
            ),
            Slider(
              value: _progress,
              onChanged: (double v) => setState(() => _progress = v),
            ),
            Text(
              '${(_progress * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        child,
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 12),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.play_arrow_rounded),
        onTap: () => unawaited(onTap()),
      ),
    );
  }
}
