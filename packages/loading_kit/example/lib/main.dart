import 'dart:async';

import 'package:flutter/material.dart';
import 'package:loading_kit/loading_kit.dart';

void main() => runApp(const GalleryApp());

/// Demo app exercising every preset, style and behaviour in the package.
class GalleryApp extends StatefulWidget {
  /// Creates the gallery.
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  LoadingPreset _preset = LoadingPreset.adaptive;
  LoadingIndicatorStyle _indicator = LoadingIndicatorStyle.arc;
  LoadingProgressStyle _progress = LoadingProgressStyle.ring;
  bool _custom = false;
  ThemeMode _mode = ThemeMode.light;

  LoadingStyle get _style {
    final LoadingStyle base = LoadingStyle(
      preset: _preset,
      indicatorStyle: _indicator,
      progressStyle: _progress,
    );
    if (!_custom) return base;
    return base.copyWith(
      indicatorBuilder: (BuildContext context, LoadingIndicatorSpec spec) =>
          _SquareIndicator(spec: spec),
    );
  }

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
      builder: LoadingKit.builder(style: _style),
      home: GalleryPage(
        preset: _preset,
        indicator: _indicator,
        progress: _progress,
        custom: _custom,
        mode: _mode,
        onPreset: (LoadingPreset v) => setState(() => _preset = v),
        onIndicator: (LoadingIndicatorStyle v) =>
            setState(() => _indicator = v),
        onProgress: (LoadingProgressStyle v) => setState(() => _progress = v),
        onCustom: (bool v) => setState(() => _custom = v),
        onMode: (ThemeMode v) => setState(() => _mode = v),
      ),
    );
  }
}

/// A deliberately un-circular custom indicator, to prove the slot is open.
class _SquareIndicator extends StatefulWidget {
  const _SquareIndicator({required this.spec});

  final LoadingIndicatorSpec spec;

  @override
  State<_SquareIndicator> createState() => _SquareIndicatorState();
}

class _SquareIndicatorState extends State<_SquareIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: Container(
        width: widget.spec.size,
        height: widget.spec.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.spec.statusColor,
            width: widget.spec.strokeWidth,
          ),
        ),
      ),
    );
  }
}

/// The gallery's single screen.
class GalleryPage extends StatefulWidget {
  /// Creates the gallery page.
  const GalleryPage({
    super.key,
    required this.preset,
    required this.indicator,
    required this.progress,
    required this.custom,
    required this.mode,
    required this.onPreset,
    required this.onIndicator,
    required this.onProgress,
    required this.onCustom,
    required this.onMode,
  });

  /// Selected preset.
  final LoadingPreset preset;

  /// Selected indeterminate form.
  final LoadingIndicatorStyle indicator;

  /// Selected determinate form.
  final LoadingProgressStyle progress;

  /// Whether the custom indicator slot is in use.
  final bool custom;

  /// Selected theme mode.
  final ThemeMode mode;

  /// Called when the preset changes.
  final ValueChanged<LoadingPreset> onPreset;

  /// Called when the indeterminate form changes.
  final ValueChanged<LoadingIndicatorStyle> onIndicator;

  /// Called when the determinate form changes.
  final ValueChanged<LoadingProgressStyle> onProgress;

  /// Called when the custom indicator is toggled.
  final ValueChanged<bool> onCustom;

  /// Called when the theme mode changes.
  final ValueChanged<ThemeMode> onMode;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  bool _barrierBusy = false;

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
            onPressed: () =>
                widget.onMode(dark ? ThemeMode.light : ThemeMode.dark),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const _SectionTitle('Preset'),
          _Chips<LoadingPreset>(
            values: LoadingPreset.values,
            selected: widget.preset,
            label: (LoadingPreset v) => v.name,
            onChanged: widget.onPreset,
          ),
          const _SectionTitle('Indeterminate form'),
          _Chips<LoadingIndicatorStyle>(
            values: LoadingIndicatorStyle.values,
            selected: widget.indicator,
            label: (LoadingIndicatorStyle v) => v.name,
            onChanged: widget.onIndicator,
          ),
          const _SectionTitle('Determinate form'),
          _Chips<LoadingProgressStyle>(
            values: LoadingProgressStyle.values,
            selected: widget.progress,
            label: (LoadingProgressStyle v) => v.name,
            onChanged: widget.onProgress,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom indicator slot'),
            subtitle: const Text(
              'Replaces every built-in form with a widget of your own.',
            ),
            value: widget.custom,
            onChanged: widget.onCustom,
          ),

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
                'Crosses the delay, so it paints — then is held for the '
                'minimum window instead of blinking out.',
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
                'Same form, settling into a cross. The throw still '
                'reaches your catch block.',
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
                // Already reported by the overlay.
              }
            },
          ),

          const _SectionTitle('Toasts — nothing is blocked'),
          _Tile(
            title: 'Plain toast',
            subtitle: 'No scrim, no blocked input, dismisses itself.',
            onTap: () async => Loading.toast('Draft saved'),
          ),
          _Tile(
            title: 'Success and error toasts',
            subtitle: 'Fired together, so they stack.',
            onTap: () async {
              Loading.toastSuccess('Order placed');
              await _wait(400);
              Loading.toastError(
                'Could not sync',
                detail: 'Retrying in the background',
              );
            },
          ),

          const _SectionTitle('Progress and cancellation'),
          _Tile(
            title: 'Determinate upload',
            subtitle:
                'Coarse jumps are interpolated into continuous motion. '
                'Switch the determinate form above to see it as a bar.',
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
                'Cancel appears after 1.5s, so quick runs never offer '
                'one.',
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
                // Already reported by the overlay.
              }
            },
          ),

          const _SectionTitle('Scoped to one widget'),
          _BarrierDemo(
            busy: _barrierBusy,
            onRun: () async {
              setState(() => _barrierBusy = true);
              await _wait(2200);
              if (mounted) setState(() => _barrierBusy = false);
            },
          ),

          const _SectionTitle('Correctness'),
          _Tile(
            title: 'Three concurrent requests',
            subtitle:
                'Reference counted — the overlay waits for the last one, '
                'not the first.',
            onTap: () async {
              await Future.wait<void>(<Future<void>>[
                Loading.run(() => _wait(900), message: 'Request A'),
                Loading.run(() => _wait(1800), message: 'Request B'),
                Loading.run(() => _wait(2700), message: 'Request C'),
              ]);
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

class _BarrierDemo extends StatelessWidget {
  const _BarrierDemo({required this.busy, required this.onRun});

  final bool busy;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LoadingBarrier(
        loading: busy,
        message: 'Saving…',
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'LoadingBarrier',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Only this card is blocked. The rest of the screen stays live '
                '— scroll it while this runs.',
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => unawaited(onRun()),
                child: const Text('Save for 2.2s'),
              ),
            ],
          ),
        ),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Wrap(
              spacing: 22,
              runSpacing: 18,
              alignment: WrapAlignment.center,
              children: <Widget>[
                for (final LoadingIndicatorStyle style
                    in LoadingIndicatorStyle.values)
                  _Labelled(
                    style.name,
                    LoadingIndicator(indicatorStyle: style, size: 40),
                  ),
                _Labelled(
                  'progress',
                  LoadingIndicator(size: 40, progress: _progress),
                ),
                const _Labelled(
                  'success',
                  LoadingIndicator(size: 40, status: LoadingStatus.success),
                ),
                const _Labelled(
                  'error',
                  LoadingIndicator(size: 40, status: LoadingStatus.error),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LoadingProgressBar(
              progress: _progress,
              color: scheme.primary,
              trackColor: scheme.primary.withValues(alpha: 0.16),
              width: 240,
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

class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((T value) {
        return ChoiceChip(
          label: Text(label(value)),
          selected: value == selected,
          onSelected: (_) => onChanged(value),
        );
      }).toList(),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      child: Column(
        children: <Widget>[
          SizedBox.square(dimension: 44, child: Center(child: child)),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
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
