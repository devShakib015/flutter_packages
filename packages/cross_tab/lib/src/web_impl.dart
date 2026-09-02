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
  CrossTab._(this.name, this._heartbeat)
      : _graceUntil = DateTime.now().add(_heartbeat) {
    _channel = web.BroadcastChannel(name);
    _channel.onmessage = ((web.MessageEvent event) {
      _receive(event.data);
    }).toJS;
    _announce('hello');
    // A tab that has just opened has not heard from anyone yet, so it cannot
    // know whether it is alone or joining a crowd. Leadership stays null for
    // one heartbeat; this settles it for a tab that really is alone.
    Timer(_heartbeat, () {
      if (!_closed) _emitPresence();
    });
    _timer = Timer.periodic(_heartbeat, (_) {
      _announce('beat');
      _prune();
    });
    // A hidden tab's timers are throttled hard — browsers clamp them to about
    // a minute — so a backgrounded tab stops beating and everyone else prunes
    // it while it still believes it leads. Two leaders is exactly the thing
    // this class exists to prevent. Beating on the visibility edge, and
    // refusing to prune on the first tick back, closes the window.
    _visibility = ((web.Event _) {
      if (_closed) return;
      _announce('beat');
      if (!web.document.hidden) {
        _skipNextPrune = true;
        _emitPresence();
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', _visibility);
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
  late final JSFunction _visibility;

  /// Leadership stays unresolved until this instant unless a peer speaks up.
  final DateTime _graceUntil;

  /// Set when this tab has just become visible again; the next prune round is
  /// skipped because everyone's timers were throttled while it was hidden.
  bool _skipNextPrune = false;
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
  Stream<TabPresence> get presence {
    // Not an async* generator. The prelude `yield current` suspends until the
    // consumer takes it, and until then nothing is subscribed to the
    // controller — so a consumer that awaits between events could miss its own
    // demotion entirely. Replaying through onListen keeps the subscription
    // live from the first moment.
    late final StreamController<TabPresence> out;
    StreamSubscription<TabPresence>? sub;
    out = StreamController<TabPresence>.broadcast(
      onListen: () {
        out.add(current);
        sub ??= _presence.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
      },
      onCancel: () async {
        await sub?.cancel();
        sub = null;
      },
    );
    return out.stream;
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
    // The envelope is JSON-encoded, so the payload has to be JSON-encodable.
    // Letting jsonEncode fail on its own produced "Converting object to an
    // encodable object failed" from somewhere deep in the post, naming a
    // type but not the field or the fact that this is a CrossTab constraint.
    try {
      _post(<String, Object?>{
        't': 'msg',
        'id': id,
        'born': _bornAt,
        'd': data,
      });
    } on JsonUnsupportedObjectError catch (e) {
      throw ArgumentError.value(
        data,
        'data',
        'CrossTab payloads are JSON-encoded, so every value must be a String, '
            'num, bool, null, List or Map of the same. '
            '${e.unsupportedObject.runtimeType} is not. Convert it first — a '
            'DateTime as an ISO string, for instance.',
      );
    }
  }

  /// Leaves the channel, telling the other tabs so they do not wait for a
  /// timeout to notice.
  void close() {
    if (_closed) return;
    _closed = true;
    _post(<String, Object?>{'t': 'bye', 'id': id, 'born': _bornAt});
    _timer.cancel();
    web.window.removeEventListener('pagehide', _unload);
    web.document.removeEventListener('visibilitychange', _visibility);
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
    // Null while this tab has heard from nobody and has not yet waited a full
    // heartbeat: "electing", not "me". Returning itself immediately meant two
    // tabs opened together both reported isLeader true for a beat, and
    // whatever the leader is supposed to do ran twice.
    if (_peers.isEmpty && DateTime.now().isBefore(_graceUntil)) return null;

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
    if (_skipNextPrune) {
      // Just came back from hidden: everyone's clocks have been throttled, so
      // one round of staleness here means nothing.
      _skipNextPrune = false;
      return;
    }
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
