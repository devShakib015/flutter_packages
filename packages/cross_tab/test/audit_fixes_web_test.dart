@TestOn('browser')
library;

// Each test pins a defect found by the 2026-09-02 audit.
import 'package:cross_tab/cross_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a brand new tab does not crown itself before hearing anyone', () async {
    // Shipped in 0.1.3: _electedLeader() had no path that returned null, so a
    // tab reported isLeader true on its very first presence event — before it
    // could possibly know whether it was joining a crowd. Two tabs opened
    // together both ran the leader's work for a beat.
    final CrossTab a = CrossTab.open(
      'grace-${DateTime.now().microsecondsSinceEpoch}',
      heartbeat: const Duration(milliseconds: 200),
    );
    addTearDown(a.close);

    expect(a.current.leader, isNull, reason: 'still electing');
    expect(a.current.isLeader, isFalse);

    // A tab that really is alone picks it up one heartbeat later.
    await Future<void>.delayed(const Duration(milliseconds: 320));
    expect(a.current.leader, a.id);
    expect(a.current.isLeader, isTrue);
  });

  test('two tabs opened together settle on exactly one leader', () async {
    final String channel = 'pair-${DateTime.now().microsecondsSinceEpoch}';
    final CrossTab a = CrossTab.open(
      channel,
      heartbeat: const Duration(milliseconds: 200),
    );
    final CrossTab b = CrossTab.open(
      channel,
      heartbeat: const Duration(milliseconds: 200),
    );
    addTearDown(a.close);
    addTearDown(b.close);

    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(a.current.leader, b.current.leader, reason: 'they must agree');
    expect(
      <bool>[a.current.isLeader, b.current.isLeader].where((bool x) => x),
      hasLength(1),
      reason: 'exactly one leader, never two',
    );
  });

  test('presence delivers to a consumer that subscribes late', () async {
    // Shipped in 0.1.3: presence was an async* generator whose `yield current`
    // prelude suspended before anything subscribed to the controller, so a
    // consumer awaiting between events could miss its own demotion.
    final CrossTab a = CrossTab.open(
      'late-${DateTime.now().microsecondsSinceEpoch}',
      heartbeat: const Duration(milliseconds: 150),
    );
    addTearDown(a.close);

    final List<TabPresence> seen = <TabPresence>[];
    final sub = a.presence.listen(seen.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, isNotEmpty, reason: 'the current state arrives immediately');
    expect(seen.first.me, a.id);
    // And the grace period resolving is delivered, not dropped.
    expect(seen.any((TabPresence p) => p.leader != null), isTrue);
  });

  test('presence is broadcast — two listeners both get it', () async {
    final CrossTab a = CrossTab.open(
      'bcast-${DateTime.now().microsecondsSinceEpoch}',
      heartbeat: const Duration(milliseconds: 150),
    );
    addTearDown(a.close);

    final List<TabPresence> one = <TabPresence>[];
    final List<TabPresence> two = <TabPresence>[];
    final s1 = a.presence.listen(one.add);
    final s2 = a.presence.listen(two.add);
    addTearDown(s1.cancel);
    addTearDown(s2.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(one, isNotEmpty);
    expect(two, isNotEmpty);
  });

  test('a non-JSON value is refused by name, not by a deep encoder error', () {
    final CrossTab a = CrossTab.open(
      'payload-${DateTime.now().microsecondsSinceEpoch}',
    );
    addTearDown(a.close);
    expect(
      () => a.send(<String, Object?>{'when': DateTime.now()}),
      throwsA(
        isA<ArgumentError>().having(
          (ArgumentError e) => e.message.toString(),
          'message',
          contains('JSON-encoded'),
        ),
      ),
    );
  });
}
