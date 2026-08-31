import 'dart:async';

import 'types.dart';

/// Cross-tab coordination, off the web.
///
/// There are no other tabs, so this behaves as the single instance it is: it
/// is always the leader, presence reports one, and sent messages have nowhere
/// to go. Code written for the web therefore runs unchanged on mobile and
/// desktop without an `if (kIsWeb)` around it.
class CrossTab {
  CrossTab._(this.name);

  /// Opens a channel. Off the web this is a well-behaved no-op.
  static CrossTab open(String name, {Duration? heartbeat}) {
    assert(name.isNotEmpty, 'a channel needs a name');
    return CrossTab._(name);
  }

  /// Whether tabs can actually talk to each other here. Always false off-web.
  static bool get isSupported => false;

  /// The channel's name.
  final String name;

  /// This instance's id.
  final String id = 'single';

  /// Never emits: there is nobody else to hear from.
  Stream<TabMessage> get messages => const Stream<TabMessage>.empty();

  /// Emits once: one tab, and it is the leader.
  Stream<TabPresence> get presence => Stream<TabPresence>.value(current);

  /// One tab, always leading.
  TabPresence get current => const TabPresence(
    tabs: <String>['single'],
    leader: 'single',
    me: 'single',
  );

  /// True, because there is nothing to compete with.
  bool get isLeader => true;

  /// Goes nowhere, and says so by doing nothing.
  void send(Map<String, Object?> data) {}

  /// Nothing to close.
  void close() {}
}
