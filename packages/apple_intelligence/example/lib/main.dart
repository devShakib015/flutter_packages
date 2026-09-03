import 'dart:async';

import 'package:apple_intelligence/apple_intelligence.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'apple_intelligence',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4C6FFF),
          useMaterial3: true,
        ),
        home: const DemoPage(),
      );
}

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('apple_intelligence'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Images'),
              Tab(text: 'Text'),
            ],
          ),
        ),
        body: const TabBarView(children: <Widget>[_ImageDemo(), _TextDemo()]),
      ),
    );
  }
}

/// Writing Tools and Genmoji only exist on a real system text view, so this
/// hosts one. Select some text and use Edit > Writing Tools, or the Genmoji
/// button in the emoji keyboard.
class _TextDemo extends StatefulWidget {
  const _TextDemo();

  @override
  State<_TextDemo> createState() => _TextDemoState();
}

class _TextDemoState extends State<_TextDemo> {
  final NativeTextController _text = NativeTextController();
  TextCapabilities? _caps;
  String _latest = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final TextCapabilities c = await _text.capabilities();
    if (mounted) setState(() => _caps = c);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppleIntelligenceTextField.isSupported) {
      return const Center(child: Text('Native text is iOS and macOS only.'));
    }
    final TextCapabilities? c = _caps;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  c == null
                      ? 'Tap Check to ask the view what it was granted'
                      : 'writing tools ${c.writingTools ? "yes" : "no"}'
                          '   ·   genmoji ${c.genmoji ? "yes" : "no"}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              OutlinedButton(onPressed: _probe, child: const Text('Check')),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: AppleIntelligenceTextField(
                  controller: _text,
                  initialText:
                      'Select this sentence and try Writing Tools — it will '
                      'rewrite it in place, and the count below updates '
                      'because the native view tells Flutter it changed.',
                  onChanged: (String v) => setState(() => _latest = v),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_latest.length} characters',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

class _ImageDemo extends StatefulWidget {
  const _ImageDemo();

  @override
  State<_ImageDemo> createState() => _DemoPageState();
}

class _DemoPageState extends State<_ImageDemo> {
  final TextEditingController _prompt = TextEditingController(
    text: 'a fox reading a map by lantern light',
  );
  ImageGenerationAvailability? _availability;
  final List<GeneratedImage> _images = <GeneratedImage>[];
  StreamSubscription<GeneratedImage>? _run;
  String? _status;
  ImageStyle _style = ImageStyle.illustration;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _run?.cancel();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final ImageGenerationAvailability a = await ImageCreator.availability();
    if (mounted) setState(() => _availability = a);
  }

  void _generate() {
    _run?.cancel();
    setState(() {
      _images.clear();
      _status = 'generating…';
    });
    _run = ImageCreator.generate(
      concepts: <ImageConcept>[ImageConcept.text(_prompt.text)],
      style: _style,
      limit: 4,
    ).listen(
      (GeneratedImage image) => setState(() => _images.add(image)),
      onError: (Object e) => setState(() => _status = '$e'),
      onDone: () => setState(() => _status = '${_images.length} image(s)'),
    );
  }

  Future<void> _sheet() async {
    try {
      final String? path = await ImagePlaygroundSheet.present(
        concepts: <ImageConcept>[ImageConcept.text(_prompt.text)],
        style: _style,
      );
      setState(() => _status = path == null ? 'cancelled' : 'saved to $path');
    } on AppleIntelligenceException catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageGenerationAvailability? a = _availability;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (a != null)
            Text(
              'status ${a.status.name}   ·   sheet ${a.sheet ? "yes" : "no"}'
              '   ·   streaming ${a.creator ? "yes" : "no"}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            decoration: const InputDecoration(
              labelText: 'Concept',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              for (final ImageStyle s in ImageStyle.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.name),
                    selected: _style == s,
                    onSelected: (_) => setState(() => _style = s),
                  ),
                ),
              const Spacer(),
              OutlinedButton(onPressed: _sheet, child: const Text('Sheet')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _generate, child: const Text('Generate')),
            ],
          ),
          const SizedBox(height: 10),
          if (_status != null)
            Text(_status!, style: Theme.of(context).textTheme.labelMedium),
          const Divider(height: 20),
          Expanded(
            child: _images.isEmpty
                ? const Center(child: Text('No images yet'))
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (BuildContext c, int i) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(_images[i].bytes, fit: BoxFit.cover),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
