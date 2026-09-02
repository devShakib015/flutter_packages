/// What another tab sent.
class TabMessage {
  /// Creates a message.
  const TabMessage({required this.data, required this.from});

  /// The payload, as JSON round-tripping produced it.
  ///
  /// Not identical to what the sender passed: the envelope is JSON-encoded,
  /// so what arrives is whatever `jsonDecode` builds. A nested map comes back
  /// as `Map<String, dynamic>` rather than the type you sent, and a `DateTime`
  /// or a custom object never makes the trip at all — see `CrossTab.send`.
  final Map<String, Object?> data;

  /// Which tab sent it. Stable for the life of that tab.
  final String from;

  @override
  String toString() => 'TabMessage(from $from, ${data.keys.join(", ")})';
}

/// Who is open, and who is in charge.
class TabPresence {
  /// Creates a presence snapshot.
  const TabPresence({
    required this.tabs,
    required this.leader,
    required this.me,
  });

  /// Every tab currently known to be open, including this one.
  final List<String> tabs;

  /// The tab elected to do work that must happen exactly once, or null while
  /// an election is still settling.
  final String? leader;

  /// This tab's id.
  final String me;

  /// Whether this tab is the one that should do the work.
  bool get isLeader => leader != null && leader == me;

  /// How many tabs are open.
  int get count => tabs.length;

  @override
  String toString() =>
      'TabPresence($count open, leader ${leader ?? "electing"}, '
      'me $me${isLeader ? " (leader)" : ""})';
}
