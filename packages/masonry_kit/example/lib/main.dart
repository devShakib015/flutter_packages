import 'package:flutter/material.dart';
import 'package:masonry_kit/masonry_kit.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'masonry_kit',
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
  final ScrollController _scroll = ScrollController();
  int _columns = 2;
  double _lowWaterMark = 0;
  double _worstJump = 0;

  @override
  void initState() {
    super.initState();
    // The point of the package, made measurable: while you drag forward, the
    // offset should never go backwards.
    _scroll.addListener(() {
      final double now = _scroll.offset;
      if (now < _lowWaterMark - 1) {
        setState(() => _worstJump = _lowWaterMark - now);
      }
      if (now > _lowWaterMark) _lowWaterMark = now;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Deterministic, uneven heights — masonry only matters when items differ.
  double _height(int i) => 70.0 + (i * 37) % 110;

  Color _tint(int i) => Colors.primaries[i % Colors.primaries.length].shade200;

  Widget _tile(String tag, int i) => DecoratedBox(
    decoration: BoxDecoration(
      color: _tint(i),
      borderRadius: BorderRadius.circular(10),
    ),
    child: SizedBox(
      height: _height(i),
      child: Center(
        child: Text(
          '$tag$i',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    ),
  );

  SliverMasonryGrid _grid(String tag, int count) => SliverMasonryGrid.count(
    crossAxisCount: _columns,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    childCount: count,
    itemBuilder: (BuildContext context, int i) => _tile(tag, i),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('masonry_kit'),
        actions: <Widget>[
          for (final int n in <int>[2, 3, 4])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                label: Text('$n'),
                selected: _columns == n,
                onSelected: (_) => setState(() => _columns = n),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: <Widget>[
                Text(
                  'Three masonry grids, one CustomScrollView',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Text(
                  _worstJump == 0
                      ? 'no backward jumps'
                      : 'jumped back ${_worstJump.toStringAsFixed(0)}px',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _worstJump == 0 ? Colors.green.shade700 : Colors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: _grid('a', 40),
                ),
                const SliverToBoxAdapter(
                  child: ListTile(
                    dense: true,
                    title: Text('— a plain sliver in between —'),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: _grid('b', 40),
                ),
                SliverList.builder(
                  itemCount: 5,
                  itemBuilder: (BuildContext c, int i) =>
                      ListTile(dense: true, title: Text('list row $i')),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: _grid('c', 40),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
