import 'dart:async';

import 'package:apple_foundation_models/apple_foundation_models.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DemoApp());

/// Demonstrates every capability of the package against the on-device model.
class DemoApp extends StatelessWidget {
  /// Creates the demo.
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'apple_foundation_models',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6B5BFF),
        brightness: Brightness.light,
      ),
      home: const DemoPage(),
    );
  }
}

/// The demo's single screen.
class DemoPage extends StatefulWidget {
  /// Creates the page.
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  ModelAvailability? _availability;
  LanguageModelSession? _session;

  final TextEditingController _prompt = TextEditingController(
    text: 'Explain gravity to a six year old.',
  );
  String _output = '';
  Map<String, Object?>? _structured;
  String _toolLog = '';
  bool _busy = false;
  StreamSubscription<String>? _streaming;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    final ModelAvailability availability =
        await AppleFoundationModels.availability();
    LanguageModelSession? session;
    if (availability.isAvailable) {
      session = await LanguageModelSession.create(
        instructions: 'You are helpful and concise.',
      );
    }
    if (!mounted) return;
    setState(() {
      _availability = availability;
      _session = session;
    });
  }

  @override
  void dispose() {
    unawaited(_streaming?.cancel());
    unawaited(_session?.dispose());
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _output = '';
      _structured = null;
    });
    try {
      await action();
    } on FoundationModelsException catch (e) {
      if (mounted) setState(() => _output = '${e.runtimeType}: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond() => _guard(() async {
    final String reply = await _session!.respond(_prompt.text);
    if (mounted) setState(() => _output = reply);
  });

  Future<void> _stream() => _guard(() async {
    final Completer<void> done = Completer<void>();
    // Each event is the whole response so far — assign, never append.
    _streaming = _session!
        .stream(_prompt.text)
        .listen(
          (String text) => setState(() => _output = text),
          onDone: done.complete,
          onError: done.completeError,
          cancelOnError: true,
        );
    await done.future;
  });

  Future<void> _triage() => _guard(() async {
    final Schema schema = Schema.object(name: 'Triage', <String, Schema>{
      'priority': Schema.oneOf(<String>['low', 'medium', 'high']),
      'summary': Schema.string(description: 'one short line'),
      'tags': Schema.array(Schema.string(), maxItems: 3),
    });
    final Map<String, Object?> result = await _session!.respondAs(
      'Triage this bug report: ${_prompt.text}',
      schema: schema,
      options: GenerationOptions.deterministic,
    );
    if (mounted) setState(() => _structured = result);
  });

  Future<void> _tool() => _guard(() async {
    setState(() => _toolLog = '');
    final LanguageModelSession tooled = await LanguageModelSession.create(
      instructions: 'Use the provided tools instead of guessing.',
      tools: <LanguageModelTool>[
        LanguageModelTool(
          name: 'getWeather',
          description:
              'Current weather for a city. Always call this '
              'rather than guessing the weather.',
          parameters: Schema.object(<String, Schema>{
            'city': Schema.string(description: 'city name'),
          }),
          handler: (Map<String, Object?> args) {
            setState(() => _toolLog = 'Dart ran getWeather($args)');
            return '18 degrees Celsius and raining';
          },
        ),
      ],
    );
    try {
      final String reply = await tooled.respond(
        'Should I take an umbrella in Dhaka right now?',
      );
      if (mounted) setState(() => _output = reply);
    } finally {
      await tooled.dispose();
    }
  });

  @override
  Widget build(BuildContext context) {
    final ModelAvailability? availability = _availability;
    final bool ready = _session != null && !_busy;

    return Scaffold(
      appBar: AppBar(title: const Text('apple_foundation_models')),
      body: availability == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                _AvailabilityCard(availability: availability),
                if (availability.isAvailable) ...<Widget>[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _prompt,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Prompt',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      FilledButton(
                        onPressed: ready ? () => unawaited(_respond()) : null,
                        child: const Text('Respond'),
                      ),
                      FilledButton.tonal(
                        onPressed: ready ? () => unawaited(_stream()) : null,
                        child: const Text('Stream'),
                      ),
                      OutlinedButton(
                        onPressed: ready ? () => unawaited(_triage()) : null,
                        child: const Text('Structured output'),
                      ),
                      OutlinedButton(
                        onPressed: ready ? () => unawaited(_tool()) : null,
                        child: const Text('Tool calling'),
                      ),
                    ],
                  ),
                  if (_busy) ...<Widget>[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (_toolLog.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    _Panel(title: 'Tool callback', body: Text(_toolLog)),
                  ],
                  if (_structured != null) ...<Widget>[
                    const SizedBox(height: 16),
                    _Panel(
                      title: 'Structured output',
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final MapEntry<String, Object?> e
                              in _structured!.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text('${e.key}: ${e.value}'),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_output.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    _Panel(title: 'Response', body: SelectableText(_output)),
                  ],
                ],
              ],
            ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({required this.availability});

  final ModelAvailability availability;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool ok = availability.isAvailable;
    final String title = ok
        ? 'The on-device model is ready'
        : (availability as ModelUnavailable).explanation;
    final String? remedy = ok
        ? null
        : (availability as ModelUnavailable).remedy;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ok ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer,
            ),
          ),
          if (remedy != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(remedy, style: TextStyle(color: scheme.onErrorContainer)),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.body});

  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}
