import 'package:fit_text/fit_text.dart';
import 'package:flutter/material.dart';

void main() => runApp(const DemoApp());

/// Demonstrates fitting, groups, and the layouts that break alternatives.
class DemoApp extends StatelessWidget {
  /// Creates the demo.
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fit_text',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F6BFF)),
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
  double _width = 320;
  final FitTextGroup _labels = FitTextGroup();

  static const String _sentence = 'Shrink me until I fit';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('fit_text')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const _Heading('Drag to resize the box'),
          Center(
            child: Container(
              width: _width,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD3E1)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const FitText(
                _sentence,
                maxLines: 1,
                minFontSize: 6,
                maxFontSize: 48,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Slider(
            min: 60,
            max: 400,
            value: _width,
            label: '${_width.round()} px',
            divisions: 68,
            onChanged: (double v) => setState(() => _width = v),
          ),

          const _Heading('One shared size across a row'),
          const Text(
            'Without a group each label picks its own size and they mismatch. '
            'With one they agree on the smallest that works.',
          ),
          const SizedBox(height: 12),
          _LabelRow(
            title: 'independent',
            children: <Widget>[
              for (final String label in _buttons)
                Expanded(child: FitText(label, maxLines: 1, minFontSize: 6)),
            ],
          ),
          const SizedBox(height: 10),
          _LabelRow(
            title: 'grouped',
            children: <Widget>[
              for (final String label in _buttons)
                Expanded(
                  child: FitText(
                    label,
                    group: _labels,
                    maxLines: 1,
                    minFontSize: 6,
                  ),
                ),
            ],
          ),

          const _Heading('Where LayoutBuilder-based sizing throws'),
          const Text(
            'IntrinsicHeight and Table both measure children before laying them '
            'out. Anything built on LayoutBuilder throws here; this does not.',
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const <Widget>[
                Expanded(
                  child: _Cell(
                    child: FitText(
                      'Inside IntrinsicHeight',
                      maxLines: 1,
                      minFontSize: 6,
                      maxFontSize: 30,
                    ),
                  ),
                ),
                Expanded(
                  child: _Cell(
                    child: Text('a taller\nneighbour\nforcing\nintrinsics'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: const Color(0xFFCBD3E1)),
            children: const <TableRow>[
              TableRow(
                children: <Widget>[
                  _Cell(
                    child: FitText(
                      'In a Table cell',
                      maxLines: 1,
                      minFontSize: 6,
                      maxFontSize: 24,
                    ),
                  ),
                  _Cell(child: Text('ordinary cell')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  static const List<String> _buttons = <String>[
    'Ok',
    'Cancel',
    'Discard everything',
  ];
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(title, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Row(children: children)),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(10), child: child);
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 10),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.3,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
