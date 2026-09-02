import 'package:anchored_list/anchored_list.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'anchored_list',
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
          title: const Text('anchored_list'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'Jump'),
              Tab(text: 'Insert above'),
            ],
          ),
        ),
        body: const TabBarView(children: <Widget>[_JumpDemo(), _PrependDemo()]),
      ),
    );
  }
}

// ---------------------------------------------------------------- jumping

class _JumpDemo extends StatefulWidget {
  const _JumpDemo();

  @override
  State<_JumpDemo> createState() => _JumpDemoState();
}

class _JumpDemoState extends State<_JumpDemo> {
  static const int _count = 1000000;

  final AnchoredListController _controller = AnchoredListController();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _field = TextEditingController(text: '842013');
  int _builtSinceJump = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
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
    return Column(
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
          // Passing our own controller is what lets the Scrollbar attach.
          child: Scrollbar(
            controller: _scroll,
            child: AnchoredList.builder(
              controller: _controller,
              scrollController: _scroll,
              itemCount: _count,
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
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- prepending

class _PrependDemo extends StatefulWidget {
  const _PrependDemo();

  @override
  State<_PrependDemo> createState() => _PrependDemoState();
}

class _PrependDemoState extends State<_PrependDemo> {
  final AnchoredListController _controller = AnchoredListController();
  final List<String> _messages = List<String>.generate(
    60,
    (int i) => 'Message $i',
  );

  /// Turn this off to watch the same insertion drag the view down.
  bool _compensate = true;
  int _loaded = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _loadOlder() {
    const int batch = 5;
    setState(() {
      _messages.insertAll(
        0,
        List<String>.generate(batch, (int i) => 'Older ${_loaded + batch - i}'),
      );
      _loaded += batch;
    });
    // The whole feature: one integer, and the pixels do not move.
    if (_compensate) _controller.itemsInsertedAbove(batch);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: <Widget>[
              FilledButton.tonal(
                onPressed: _loadOlder,
                child: const Text('Load 5 older'),
              ),
              const Spacer(),
              const Text('itemsInsertedAbove'),
              Switch(
                value: _compensate,
                onChanged: (bool v) => setState(() => _compensate = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _compensate
                  ? 'The view holds its place as history arrives.'
                  : 'Without it, every insert drags the view down.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ),
        const Divider(height: 20),
        Expanded(
          child: AnchoredList.separated(
            controller: _controller,
            initialIndex: 20,
            itemCount: _messages.length,
            itemBuilder: (BuildContext context, int index) {
              final bool older = _messages[index].startsWith('Older');
              return ListTile(
                dense: true,
                title: Text(_messages[index]),
                textColor: older ? Theme.of(context).hintColor : null,
              );
            },
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
          ),
        ),
      ],
    );
  }
}
