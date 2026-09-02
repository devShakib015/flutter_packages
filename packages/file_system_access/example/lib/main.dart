import 'package:file_system_access/file_system_access.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'file_system_access',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4C6FFF),
          useMaterial3: true,
        ),
        home: const EditorPage(),
      );
}

/// A text editor that saves back into the file the user opened, and finds it
/// again after a reload.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  static const String _rememberedKey = 'last-document';

  final TextEditingController _text = TextEditingController();
  FileHandle? _file;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// The whole point: after a reload, the file the user last opened is still
  /// reachable without asking them to find it again.
  Future<void> _restore() async {
    if (!FileSystemAccess.isSupported) return;
    final FileHandle? remembered = await FileSystemAccess.recallFile(
      _rememberedKey,
    );
    if (remembered == null || !mounted) return;
    final FilePermission p = await remembered.permission();
    setState(() {
      _file = remembered;
      _status = p == FilePermission.granted
          ? 'reopened ${remembered.name} from last time'
          : 'found ${remembered.name} from last time — grant access to read it';
    });
    if (p == FilePermission.granted) await _read();
  }

  Future<void> _open() async {
    final List<FileHandle> chosen = await FileSystemAccess.openFiles(
      types: <FilePickerType>[
        FilePickerType.mime(
            'text/plain',
            <String>[
              '.txt',
              '.md',
              '.dart',
            ],
            description: 'Text'),
      ],
    );
    if (chosen.isEmpty) return setState(() => _status = 'cancelled');
    setState(() => _file = chosen.first);
    await FileSystemAccess.remember(_rememberedKey, chosen.first);
    await _read();
  }

  Future<void> _read() async {
    final FileHandle? f = _file;
    if (f == null) return;
    try {
      final String body = await f.readText();
      if (!mounted) return;
      setState(() {
        _text.text = body;
        _status = 'opened ${f.name} (${body.length} characters)';
      });
    } on FileSystemAccessException catch (e) {
      setState(() => _status = '$e');
    }
  }

  /// Saves into the same file. No download, no `document (3).txt`.
  Future<void> _save() async {
    FileHandle? f = _file;
    f ??= await FileSystemAccess.saveFile(
      suggestedName: 'untitled.txt',
      types: <FilePickerType>[
        FilePickerType.mime(
            'text/plain',
            <String>[
              '.txt',
            ],
            description: 'Text'),
      ],
    );
    if (f == null) return setState(() => _status = 'cancelled');
    if (await f.permission(write: true) != FilePermission.granted) {
      if (await f.requestPermission(write: true) != FilePermission.granted) {
        return setState(() => _status = 'write permission refused');
      }
    }
    await f.writeText(_text.text);
    await FileSystemAccess.remember(_rememberedKey, f);
    if (!mounted) return;
    setState(() {
      _file = f;
      _status = 'saved into ${f!.name} — same file, no copy';
    });
  }

  @override
  Widget build(BuildContext context) {
    final FileSystemAccessSupport s = FileSystemAccess.support;
    return Scaffold(
      appBar: AppBar(
        title: const Text('file_system_access'),
        actions: <Widget>[
          TextButton(
            onPressed: s.openPicker ? _open : null,
            child: const Text('Open'),
          ),
          TextButton(
            onPressed: s.savePicker ? _save : null,
            child: const Text('Save'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!s.anyPicker)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This browser has no file pickers. Chrome and Edge do; '
                    'Firefox and Safari largely do not.',
                  ),
                ),
              ),
            Text(
              'open ${s.openPicker} · save ${s.savePicker} · '
              'directory ${s.directoryPicker} · private ${s.originPrivate}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            if (_status.isNotEmpty)
              Text(_status, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _text,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Open a file, edit it, then Save. '
                      'Reload the page — it comes back.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
