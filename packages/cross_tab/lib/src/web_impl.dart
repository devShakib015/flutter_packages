import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'types.dart';

/// Coordinate the browser tabs of one app.
///
/// Three things every multi-tab web app eventually needs and the platform only
/// half-provides:
///
/// * **Messages.** `BroadcastChannel` carries them, but as untyped structured
///   clones with no sender identity, so every app reinvents an envelope.
/// * **Presence.** The platform will not tell you how many tabs are open. It
///   has to be maintained by heartbeat, including noticing a tab that was
///   closed without warning.
/// * **A leader.** Exactly one tab should poll the server, hold the socket, or
///   raise the notification. Electing one is the part that is genuinely fiddly
///   — two tabs opened in the same millisecond must still agree, and the
///   leader disappearing must trigger a new election rather than silence.
///
/// ```dart
/// final tabs = CrossTab.open('app');
/// tabs.presence.listen((p) {
///   if (p.isLeader) startPolling(); else stopPolling();
/// });
/// ```
class CrossTab {
  CrossTab._(this.name, this._heartbeat) {
    _channel = web.BroadcastChannel(name);
    _channel.onmessage = ((web.MessageEvent event) {
      _receive(event.data);
    }).toJS;
    _announce('hello');
    _timer = Timer.periodic(_heartbeat, (_) {
      _announce('beat');
      _prune();
    });
    // A tab closed by the user, rather than by calling close(), still owes the
    // others a goodbye — otherwise they wait a full timeout to notice.
    _unload = ((web.Event _) => close()).toJS;
    web.window.addEventListener('pagehide', _unload);
  }

  /// Opens a channel that every tab of this app sharing [name] can see.
  ///
  /// [heartbeat] is how often presence is refreshed. A tab is considered gone
  /// after three missed beats, so shorter means faster detection and more
  /// chatter. The default suits a UI; tests want something much shorter.
  static CrossTab open(String name, {Duration? heartbeat}) {
    assert(name.isNotEmpty, 'a channel needs a name');
    return CrossTab._(name, heartbeat ?? const Duration(milliseconds: 800));
  }

  /// Whether this browser has `BroadcastChannel`. Every current one does.
  static bool get isSupported => true;

  /// The channel's name.
  final String name;

  /// This tab's id. Stable while the tab lives, and unique across tabs.
  final String id = _newId();

  final Duration _heartbeat;
  late final web.BroadcastChannel _channel;
  late final Timer _timer;
  late final JSFunction _unload;
  final int _bornAt = DateTime.now().microsecondsSinceEpoch;

  final Map<String, _Peer> _peers = <String, _Peer>{};
  final StreamController<TabMessage> _messages =
      StreamController<TabMessage>.broadcast();
  final StreamController<TabPresence> _presence =
      StreamController<TabPresence>.broadcast();
  String? _lastLeader;
  bool _closed = false;

  /// Messages from other tabs.
  ///
  /// A tab never receives its own — that is `BroadcastChannel`'s behaviour and
  /// it is the useful one, since the sender already knows what it sent.
  Stream<TabMessage> get messages => _messages.stream;

  /// Presence, emitted whenever the set of tabs or the leader changes.
  ///
  /// Emits the current state immediately on subscription, so a listener does
  /// not have to wait for the next change to learn where it stands.
  Stream<TabPresence> get presence async* {
    yield current;
    yield* _presence.stream;
  }

  /// Who is open right now, and who leads.
  TabPresence get current {
    final List<String> tabs = <String>[id, ..._peers.keys]..sort();
    return TabPresence(tabs: tabs, leader: _electedLeader(), me: id);
  }

  /// Whether this tab should do the work that must happen exactly once.
  bool get isLeader => _electedLeader() == id;

  /// Sends [data] to every other tab.
  void send(Map<String, Object?> data) {
    if (_closed) {
      throw StateError('This CrossTab has been closed.');
    }
    _post(<String, Object?>{'t': 'msg', 'id': id, 'born': _bornAt, 'd': data});
  }

  /// Leaves the channel, telling the other tabs so they do not wait for a
  /// timeout to notice.
  void close() {
    if (_closed) return;
    _closed = true;
    _post(<String, Object?>{'t': 'bye', 'id': id, 'born': _bornAt});
    _timer.cancel();
    web.window.removeEventListener('pagehide', _unload);
    _channel.close();
    _messages.close();
    _presence.close();
  }

  // ------------------------------------------------------------- internals

  /// The oldest tab leads, with the id as a tiebreak.
  ///
  /// Two tabs opened in the same microsecond would otherwise each think the
  /// other should lead, or both lead. Comparing the id second makes the answer
  /// total and identical on every tab, which is what matters: they must all
  /// reach the same conclusion without talking about it further.
  String? _electedLeader() {
    String bestId = id;
    int bestBorn = _bornAt;
    for (final MapEntry<String, _Peer> e in _peers.entries) {
      final bool older = e.value.bornAt < bestBorn;
      final bool tie =
          e.value.bornAt == bestBorn && e.key.compareTo(bestId) < 0;
      if (older || tie) {
        bestId = e.key;
        bestBorn = e.value.bornAt;
      }
    }
    return bestId;
  }

  void _announce(String kind) {
    _post(<String, Object?>{'t': kind, 'id': id, 'born': _bornAt});
  }

  void _post(Map<String, Object?> envelope) {
    if (_closed && envelope['t'] != 'bye') return;
    _channel.postMessage(jsonEncode(envelope).toJS);
  }

  void _receive(JSAny? raw) {
    if (_closed || raw == null) return;
    final Object? decoded = jsonDecode((raw as JSString).toDart);
    if (decoded is! Map<String, Object?>) return;
    final String? peer = decoded['id'] as String?;
    if (peer == null || peer == id) return;

    switch (decoded['t']) {
      case 'hello':
        _seen(peer, decoded['born'] as int?);
        // Answer a newcomer directly so it learns about us now rather than at
        // its next heartbeat. Without this, a tab opening into an established
        // set believes it is alone for a moment and briefly claims leadership.
        _announce('beat');
      case 'beat':
        _seen(peer, decoded['born'] as int?);
      case 'bye':
        if (_peers.remove(peer) != null) _emitPresence();
      case 'msg':
        _seen(peer, decoded['born'] as int?);
        final Object? payload = decoded['d'];
        if (payload is Map<String, Object?>) {
          _messages.add(TabMessage(data: payload, from: peer));
        }
    }
  }

  void _seen(String peer, int? bornAt) {
    final bool isNew = !_peers.containsKey(peer);
    _peers[peer] = _Peer(
      bornAt: bornAt ?? DateTime.now().microsecondsSinceEpoch,
      lastSeen: DateTime.now(),
    );
    if (isNew) _emitPresence();
  }

  /// Drops tabs that have missed three beats — a crash or a killed process
  /// never sends a goodbye.
  void _prune() {
    final DateTime cutoff = DateTime.now().subtract(_heartbeat * 3);
    final List<String> gone = <String>[
      for (final MapEntry<String, _Peer> e in _peers.entries)
        if (e.value.lastSeen.isBefore(cutoff)) e.key,
    ];
    if (gone.isEmpty) return;
    for (final String peer in gone) {
      _peers.remove(peer);
    }
    _emitPresence();
  }

  void _emitPresence() {
    if (_closed || _presence.isClosed) return;
    final TabPresence snapshot = current;
    _presence.add(snapshot);
    if (snapshot.leader != _lastLeader) _lastLeader = snapshot.leader;
  }

  static final math.Random _random = math.Random();

  static String _newId() {
    const String alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(<int>[
      for (int i = 0; i < 12; i++)
        alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
    ]);
  }
}

class _Peer {
  const _Peer({required this.bornAt, required this.lastSeen});
  final int bornAt;
  final DateTime lastSeen;
}
