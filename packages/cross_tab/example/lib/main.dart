import 'dart:async';

import 'package:cross_tab/cross_tab.dart';
import 'package:flutter/material.dart';

import 'panel_demo.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'cross_tab',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4C6FFF),
          useMaterial3: true,
        ),
        home: const PanelDemo(),
      );
}

/// Open this page in two or three browser tabs to see it work.
class TabsPage extends StatefulWidget {
  const TabsPage({super.key});

  @override
  State<TabsPage> createState() => _TabsPageState();
}

class _TabsPageState extends State<TabsPage> {
  final CrossTab _tabs = CrossTab.open('cross-tab-demo');
  final List<String> _log = <String>[];
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  TabPresence? _presence;
  Timer? _leaderWork;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _tabs.messages.listen((TabMessage m) {
        setState(() => _log.insert(0, '${m.from.substring(0, 4)} → ${m.data}'));
      }),
    );
    _subs.add(
      _tabs.presence.listen((TabPresence p) {
        setState(() => _presence = p);
        // The point of a leader: exactly one tab does this, and if that tab
        // closes another picks it up without anything being told to.
        if (p.isLeader) {
          _leaderWork ??= Timer.periodic(const Duration(seconds: 3), (_) {
            setState(
              () => _log.insert(0, 'leader tick (only one tab does this)'),
            );
          });
        } else {
          _leaderWork?.cancel();
          _leaderWork = null;
        }
      }),
    );
  }

  @override
  void dispose() {
    _leaderWork?.cancel();
    for (final StreamSubscription<Object?> s in _subs) {
      s.cancel();
    }
    _tabs.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TabPresence? p = _presence;
    return Scaffold(
      appBar: AppBar(
        title: const Text('cross_tab'),
        actions: <Widget>[
          if (p != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text(p.isLeader ? 'leader' : 'follower'),
                backgroundColor:
                    p.isLeader ? Colors.green.shade100 : Colors.grey.shade200,
              ),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!CrossTab.isSupported)
              const Text(
                'Not the web — this is a single instance, always the '
                'leader. Which is the correct answer, not a fallback.',
              ),
            Text(
              p == null
                  ? 'starting…'
                  : '${p.count} tab(s) open · this one is ${p.me.substring(0, 4)}'
                      ' · leader ${p.leader?.substring(0, 4) ?? "electing"}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Open this page in another tab to watch it join.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                FilledButton(
                  onPressed: () => _tabs.send(<String, Object?>{
                    'hello': 'from ${_tabs.id.substring(0, 4)}',
                    'at': DateTime.now().toIso8601String().substring(11, 19),
                  }),
                  child: const Text('Send to the other tabs'),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: _log.isEmpty
                  ? const Center(child: Text('nothing heard yet'))
                  : ListView.builder(
                      itemCount: _log.length,
                      itemBuilder: (BuildContext c, int i) =>
                          ListTile(dense: true, title: Text(_log[i])),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
