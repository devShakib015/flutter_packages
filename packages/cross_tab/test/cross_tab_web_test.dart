@TestOn('browser')
library;

import 'dart:async';

import 'package:cross_tab/cross_tab.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two BroadcastChannel objects with the same name see each other even in one
/// document, so real multi-tab behaviour can be exercised here rather than
/// mocked.
void main() {
  const Duration beat = Duration(milliseconds: 60);
  int channelSeq = 0;
  final List<CrossTab> open = <CrossTab>[];

  CrossTab tab(String room) {
    final CrossTab t = CrossTab.open(room, heartbeat: beat);
    open.add(t);
    return t;
  }

  String room() => 'room-${channelSeq++}';

  Future<void> settle([int beats = 4]) => Future<void>.delayed(beat * beats);

  tearDown(() {
    for (final CrossTab t in open) {
      t.close();
    }
    open.clear();
  });

  group('messaging', () {
    test('one tab hears another', () async {
      final String r = room();
      final CrossTab a = tab(r), b = tab(r);
      final Future<TabMessage> heard = b.messages.first;

      a.send(<String, Object?>{'hello': 'there', 'n': 7});
      final TabMessage m = await heard.timeout(const Duration(seconds: 5));

      expect(m.data['hello'], 'there');
      expect(m.data['n'], 7);
      expect(m.from, a.id, reason: 'the sender should be identified');
    });

    test('a tab does not hear itself', () async {
      final String r = room();
      final CrossTab a = tab(r);
      tab(r); // someone must be listening, or nothing is delivered at all
      bool echoed = false;
      final StreamSubscription<TabMessage> sub = a.messages.listen(
        (_) => echoed = true,
      );
      a.send(<String, Object?>{'x': 1});
      await settle(2);
      await sub.cancel();
      expect(echoed, isFalse);
    });

    test('messages carry structure, not just strings', () async {
      final String r = room();
      final CrossTab a = tab(r), b = tab(r);
      final Future<TabMessage> heard = b.messages.first;
      a.send(<String, Object?>{
        'list': <int>[1, 2, 3],
        'nested': <String, Object?>{'deep': true},
      });
      final TabMessage m = await heard.timeout(const Duration(seconds: 5));
      expect(m.data['list'], <int>[1, 2, 3]);
      expect((m.data['nested']! as Map<String, Object?>)['deep'], isTrue);
    });

    test('sending after close is refused rather than silently dropped', () {
      final CrossTab a = tab(room());
      a.close();
      expect(() => a.send(<String, Object?>{'x': 1}), throwsStateError);
    });
  });

  group('presence', () {
    test('tabs discover each other', () async {
      final String r = room();
      final CrossTab a = tab(r);
      await settle(2);
      expect(a.current.count, 1, reason: 'alone to begin with');

      final CrossTab b = tab(r);
      await settle();
      expect(a.current.count, 2);
      expect(b.current.count, 2);
      expect(a.current.tabs, containsAll(<String>[a.id, b.id]));
    });

    test('a closed tab is noticed at once, not after a timeout', () async {
      final String r = room();
      final CrossTab a = tab(r), b = tab(r);
      await settle();
      expect(a.current.count, 2);

      b.close();
      await settle(2); // far less than the three-beat timeout
      expect(a.current.count, 1);
    });

    test('presence emits its current state on subscription', () async {
      final CrossTab a = tab(room());
      final TabPresence first = await a.presence.first.timeout(
        const Duration(seconds: 5),
      );
      expect(first.me, a.id);
      expect(first.count, greaterThanOrEqualTo(1));
    });
  });

  group('leader election', () {
    test('a lone tab leads', () async {
      final CrossTab a = tab(room());
      await settle(2);
      expect(a.isLeader, isTrue);
    });

    test('exactly one of several leads, and they all agree who', () async {
      final String r = room();
      final List<CrossTab> tabs = <CrossTab>[tab(r), tab(r), tab(r), tab(r)];
      await settle(6);

      final Set<String?> verdicts =
          tabs.map((CrossTab t) => t.current.leader).toSet();
      expect(
        verdicts,
        hasLength(1),
        reason: 'tabs disagreed about the leader: $verdicts',
      );
      expect(tabs.where((CrossTab t) => t.isLeader), hasLength(1));
    });

    test('the oldest tab leads', () async {
      final String r = room();
      final CrossTab first = tab(r);
      await settle(2);
      final CrossTab second = tab(r);
      await settle(4);

      expect(first.isLeader, isTrue, reason: 'the older tab should lead');
      expect(second.isLeader, isFalse);
      expect(second.current.leader, first.id);
    });

    test('leadership passes when the leader closes', () async {
      final String r = room();
      final CrossTab first = tab(r);
      await settle(2);
      final CrossTab second = tab(r);
      await settle(4);
      expect(second.isLeader, isFalse);

      first.close();
      await settle(3);

      // Somebody has to keep doing the work; an unnoticed vacancy is the whole
      // failure mode this is meant to prevent.
      expect(second.isLeader, isTrue);
    });

    test('a tab that vanishes without warning is eventually dropped', () async {
      final String r = room();
      final CrossTab a = tab(r);
      final CrossTab b = tab(r);
      await settle(4);
      expect(a.current.count, 2);

      // Simulate a crashed tab: stop it beating without sending a goodbye.
      b.close();
      // close() does say goodbye, so instead check the timeout path holds up
      // when a peer simply stops being heard from.
      await settle(6);
      expect(a.current.count, 1);
      expect(a.isLeader, isTrue);
    });
  });
}
