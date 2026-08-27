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

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
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
    _run =
        ImageCreator.generate(
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
    return Scaffold(
      appBar: AppBar(title: const Text('apple_intelligence')),
      body: Padding(
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
                FilledButton(
                  onPressed: _generate,
                  child: const Text('Generate'),
                ),
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
                        child: Image.memory(
                          _images[i].bytes,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
