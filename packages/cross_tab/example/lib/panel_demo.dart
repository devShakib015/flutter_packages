import 'dart:async';

import 'package:cross_tab/cross_tab.dart';
import 'package:flutter/material.dart';

/// Four independent [CrossTab]s in one page.
///
/// Not a simulation: two BroadcastChannels with the same name see each other
/// inside a single document exactly as they do across real browser tabs, which
/// is how this package's own tests run four "tabs" in one test. So the
/// election below is the real election, and closing a panel really does
/// trigger a real re-election.
///
/// Opening this page in two browser windows works too — you then have eight.
class PanelDemo extends StatefulWidget {
  /// Creates the demo.
  const PanelDemo({super.key});

  @override
  State<PanelDemo> createState() => _PanelDemoState();
}

class _PanelDemoState extends State<PanelDemo> {
  final List<int> _open = <int>[0, 1, 2, 3];
  int _next = 4;

  /// Set by `?auto=1`: every panel broadcasts once shortly after start, so a
  /// headless screenshot catches a populated page. `?auto=1&drop=1` also
  /// closes the leader, to capture the re-election. Only used by
  /// `tool/shoot.sh`; the page is fully interactive without them.
  static bool get _auto => Uri.base.queryParameters['auto'] == '1';
  static bool get _drop => Uri.base.queryParameters['drop'] == '1';

  @override
  void initState() {
    super.initState();
    if (_auto && _drop) {
      Timer(const Duration(milliseconds: 2600), () {
        if (!mounted || _open.length < 2) return;
        setState(() => _open.removeAt(0));
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F4F8),
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('cross_tab'),
      titleTextStyle: const TextStyle(
        color: Color(0xFF11142B),
        fontSize: 19,
        fontWeight: FontWeight.w600,
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(30),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 10, right: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Every panel is a real, independent tab. One is elected leader; '
              'close it and another takes over on its own.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton.icon(
            onPressed: () => setState(() => _open.add(_next++)),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New tab'),
          ),
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The key goes on the Expanded, not on the panel inside it.
          // Flutter matches children positionally by (type, key), and an
          // unkeyed Expanded that shifts left takes its whole subtree with
          // it — every remaining tab would be torn down and rebuilt with a
          // new id, which is the opposite of what this demo is showing.
          for (final int key in _open) ...<Widget>[
            Expanded(
              key: ValueKey<int>(key),
              child: _TabPanel(
                onClose: _open.length > 1
                    ? () => setState(() => _open.remove(key))
                    : null,
              ),
            ),
            if (key != _open.last)
              SizedBox(key: ValueKey<String>('gap-$key'), width: 12),
          ],
        ],
      ),
    ),
  );
}

class _TabPanel extends StatefulWidget {
  const _TabPanel({this.onClose});

  final VoidCallback? onClose;

  @override
  State<_TabPanel> createState() => _TabPanelState();
}

class _TabPanelState extends State<_TabPanel> {
  static bool get _autoMode => Uri.base.queryParameters['auto'] == '1';

  late final CrossTab _tab = CrossTab.open('cross-tab-demo');
  Timer? _auto;
  final List<String> _log = <String>[];
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  TabPresence? _presence;
  Timer? _leaderWork;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(
        _tab.messages.listen((TabMessage m) {
          if (!mounted) return;
          setState(
            () => _log.insert(0, '← ${_short(m.from)}  ${m.data['say']}'),
          );
        }),
      )
      ..add(
        _tab.presence.listen((TabPresence p) {
          if (!mounted) return;
          setState(() => _presence = p);
          if (p.isLeader) {
            if (_autoMode) {
              // A never-ending periodic timer stops the page ever going idle,
              // and a headless screenshot then waits for it forever. In auto
              // mode show a fixed count instead of running the clock.
              _ticks = 12;
            } else {
              _leaderWork ??= Timer.periodic(const Duration(seconds: 2), (_) {
                if (!mounted) return;
                setState(() => _ticks++);
              });
            }
          } else {
            _leaderWork?.cancel();
            _leaderWork = null;
          }
        }),
      );

    if (_autoMode) {
      // Stagger, so the log order is stable between runs.
      _auto = Timer(
        Duration(milliseconds: 900 + 220 * (hashCode.abs() % 4)),
        () => _tab.send(<String, Object?>{'say': 'hello'}),
      );
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _leaderWork?.cancel();
    for (final StreamSubscription<Object?> s in _subs) {
      s.cancel();
    }
    _tab.close();
    super.dispose();
  }

  static String _short(String id) => id.substring(0, 4);

  @override
  Widget build(BuildContext context) {
    final TabPresence? p = _presence;
    final bool leader = p?.isLeader ?? false;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: leader ? const Color(0xFF16A34A) : const Color(0xFFE2E4ED),
          width: leader ? 1.6 : 1,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: leader ? const Color(0xFFEAF7EF) : const Color(0xFFF7F8FB),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  leader ? Icons.star_rounded : Icons.circle_outlined,
                  size: 16,
                  color: leader
                      ? const Color(0xFF16A34A)
                      : Colors.grey.shade500,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    p == null ? '…' : 'tab ${_short(p.me)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  InkWell(
                    onTap: widget.onClose,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close,
                        size: 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Badge(
                  text: leader ? 'LEADER' : 'follower',
                  colour: leader
                      ? const Color(0xFF16A34A)
                      : Colors.grey.shade500,
                  filled: leader,
                ),
                const SizedBox(height: 10),
                Text(
                  leader
                      ? 'Polling the server.\n$_ticks refreshes so far.'
                      : 'Idle. The leader\npolls for all of us.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: leader
                        ? const Color(0xFF166534)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () =>
                        _tab.send(<String, Object?>{'say': 'hello'}),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('Broadcast'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _log.isEmpty
                ? Center(
                    child: Text(
                      'nothing heard',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: _log.length,
                    itemBuilder: (BuildContext c, int i) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        _log[i],
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                          color: Color(0xFF3B3F58),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.colour,
    required this.filled,
  });

  final String text;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? colour : Colors.transparent,
      border: Border.all(color: colour),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: filled ? Colors.white : colour,
      ),
    ),
  );
}
