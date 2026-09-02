import 'package:ar_quick_look/ar_quick_look.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'ar_quick_look',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4C6FFF),
          useMaterial3: true,
        ),
        home: const PreviewPage(),
      );
}

class PreviewPage extends StatefulWidget {
  const PreviewPage({super.key});

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  final TextEditingController _path = TextEditingController();
  String _status = '';
  bool _scaling = true;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final bool ok = await ArQuickLook.canPreview(_path.text.trim());
    setState(
      () => _status = ok
          ? 'Quick Look will show this file.'
          : 'Quick Look will not show this file — wrong format, or not there.',
    );
  }

  Future<void> _show() async {
    try {
      setState(() => _status = 'presenting…');
      await ArQuickLook.present(
        _path.text.trim(),
        allowsContentScaling: _scaling,
      );
      // The future completes on dismissal, so this runs after the user closes.
      setState(() => _status = 'closed by the user');
    } on ArQuickLookException catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ar_quick_look')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              ArQuickLook.isSupported
                  ? 'AR Quick Look is available on this device.'
                  : 'AR Quick Look is iOS only. Nothing here will work.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'Path to a .usdz or .reality file',
                border: OutlineInputBorder(),
                isDense: true,
                helperText: 'A model exported by roomplan works here.',
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Let the user resize the model'),
              subtitle: const Text(
                'Turn off when the size is the point — furniture, for instance.',
              ),
              value: _scaling,
              onChanged: (bool v) => setState(() => _scaling = v),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                OutlinedButton(
                  onPressed: ArQuickLook.isSupported ? _check : null,
                  child: const Text('Can preview?'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: ArQuickLook.isSupported ? _show : null,
                  child: const Text('Show in AR'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_status.isNotEmpty)
              Text(_status, style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Text(
              'Bundled models work too:\n'
              "await ArQuickLook.presentAsset('assets/chair.usdz');\n"
              'Quick Look needs a real file, so the asset is copied out first.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
