@TestOn('vm')
library;

import 'package:cross_tab/cross_tab.dart';
import 'package:flutter_test/flutter_test.dart';

/// Off the web there is one instance of the app, so the answers are not
/// "unsupported" — they are the truthful single-tab answers. That is what lets
/// the same code run on mobile without an `if (kIsWeb)` around it.
void main() {
  group('off the web', () {
    test('reports itself unsupported but still usable', () {
      expect(CrossTab.isSupported, isFalse);
      final CrossTab t = CrossTab.open('app');
      addTearDown(t.close);
      expect(t.name, 'app');
    });

    test('is always the leader, because it is the only one', () {
      final CrossTab t = CrossTab.open('app');
      addTearDown(t.close);
      expect(t.isLeader, isTrue);
      expect(t.current.isLeader, isTrue);
      expect(t.current.count, 1);
      expect(t.current.leader, t.current.me);
    });

    test('sending goes nowhere and does not throw', () {
      final CrossTab t = CrossTab.open('app');
      addTearDown(t.close);
      expect(() => t.send(<String, Object?>{'x': 1}), returnsNormally);
    });

    test('messages never arrive, and the stream does not hang open', () async {
      final CrossTab t = CrossTab.open('app');
      addTearDown(t.close);
      expect(await t.messages.isEmpty, isTrue);
    });

    test('presence emits once and describes a single tab', () async {
      final CrossTab t = CrossTab.open('app');
      addTearDown(t.close);
      final List<TabPresence> seen = await t.presence.toList();
      expect(seen, hasLength(1));
      expect(seen.single.count, 1);
      expect(seen.single.isLeader, isTrue);
    });

    test('rejects an unnamed channel', () {
      expect(() => CrossTab.open(''), throwsAssertionError);
    });
  });

  group('presence value semantics', () {
    test('isLeader compares the leader against this tab', () {
      const TabPresence mine = TabPresence(
        tabs: <String>['a', 'b'],
        leader: 'a',
        me: 'a',
      );
      const TabPresence theirs = TabPresence(
        tabs: <String>['a', 'b'],
        leader: 'a',
        me: 'b',
      );
      expect(mine.isLeader, isTrue);
      expect(theirs.isLeader, isFalse);
      expect(mine.count, 2);
    });

    test('an unsettled election is not a leadership claim', () {
      const TabPresence electing = TabPresence(
        tabs: <String>['a'],
        leader: null,
        me: 'a',
      );
      expect(electing.isLeader, isFalse);
      expect(electing.toString(), contains('electing'));
    });

    test('a message reports who sent it', () {
      const TabMessage m = TabMessage(
        data: <String, Object?>{'k': 1},
        from: 'other',
      );
      expect(m.from, 'other');
      expect(m.toString(), contains('other'));
    });
  });
}
