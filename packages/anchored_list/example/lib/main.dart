import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Demo());

/// Jumps around a million items to show the cost does not change.
class Demo extends StatelessWidget {
  /// Creates the demo.
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'anchored_list',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF3B5BFF)),
    home: const DemoPage(),
  );
}

/// The demo's single screen.
class DemoPage extends StatefulWidget {
  /// Creates the page.
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  static const int _count = 1000000;

  final AnchoredListController _controller = AnchoredListController();
  final TextEditingController _field = TextEditingController(text: '842013');
  int _builtSinceJump = 0;

  @override
  void dispose() {
    _controller.dispose();
    _field.dispose();
    super.dispose();
  }

  void _jump({required bool animated}) {
    final int? target = int.tryParse(_field.text.trim());
    if (target == null) return;
    setState(() => _builtSinceJump = 0);
    if (animated) {
      _controller.animateToIndex(target, alignment: 0.5);
    } else {
      _controller.jumpToIndex(target, alignment: 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('anchored_list')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _field,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Index (0 – 999,999)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: () => _jump(animated: false),
                  child: const Text('Jump'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _jump(animated: true),
                  child: const Text('Animate'),
                ),
              ],
            ),
          ),
          // The counter is the point: it barely moves however far you jump.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Text(
                  'Widgets built since the last jump: $_builtSinceJump',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                ValueListenableBuilder<List<ItemPosition>>(
                  valueListenable: _controller.itemPositions,
                  builder: (BuildContext context, List<ItemPosition> p, _) {
                    final Iterable<ItemPosition> visible = p.where(
                      (ItemPosition e) => e.isVisible,
                    );
                    if (visible.isEmpty) return const SizedBox.shrink();
                    return Text(
                      'showing ${visible.first.index}–${visible.last.index}',
                      style: Theme.of(context).textTheme.labelMedium,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: AnchoredList.builder(
              controller: _controller,
              itemCount: _count,
              initialIndex: 0,
              itemBuilder: (BuildContext context, int index) {
                _builtSinceJump++;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text(
                      '${index % 100}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  title: Text('Item $index'),
                  subtitle: index % 7 == 0
                      ? const Text('a taller row, to vary the extents')
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
