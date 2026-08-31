## 0.1.0

Initial release: cross-tab coordination for Flutter Web.

- `CrossTab.open(name)` joins every tab of your app sharing that name.
- **Leader election.** Exactly one tab is elected to do work that must happen
  once — polling, a socket, a notification — and leadership moves when that tab
  closes. The oldest tab leads, with the id as a tiebreak so tabs opened in the
  same microsecond still reach the same answer.
- **Presence.** `count`, `tabs`, `leader`, `isLeader`, emitted on change and on
  subscription. A closed tab says goodbye so the others react immediately; a
  crashed one is dropped after three missed heartbeats.
- **Messages** with a sender id, carrying structure rather than strings. A tab
  never hears its own.
- Off the web the package still compiles and behaves as the single instance it
  is: one tab, always the leader. That is the truthful answer, and it means
  leader logic needs no `if (kIsWeb)` around it.

Verified in a real browser: `flutter test --platform chrome` exercises four
tabs agreeing on one leader, the oldest winning, and leadership passing on
close — using two `BroadcastChannel` objects in one document, which see each
other exactly as separate tabs do.
