# cross_tab

Coordinate the browser tabs of a Flutter Web app.

```dart
final tabs = CrossTab.open('my-app');

tabs.presence.listen((p) {
  if (p.isLeader) {
    startPolling();
  } else {
    stopPolling();
  }
});

tabs.messages.listen((m) => print('${m.from} said ${m.data}'));
tabs.send({'signedOut': true});
```

![Four tabs, one leader](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/cross_tab/doc/leader.png)

Every panel above is a real, independent tab. One is elected leader and does
the polling; close it and another takes over on its own, keeping what it had
already received.

![Automatic re-election](https://raw.githubusercontent.com/devShakib015/flutter_packages/HEAD/packages/cross_tab/doc/election.png)


## The problem

Open your app in two tabs and things start going wrong quietly. Both poll the
server. Both hold a socket. Both raise the same notification. The user signs
out in one and the other carries on as though nothing happened.

The browser gives you `BroadcastChannel` and stops there. What is missing is
everything around it.

| what you need | what the platform gives you |
| --- | --- |
| messages with a sender | untyped structured clones, no identity |
| how many tabs are open | nothing — you maintain it by heartbeat |
| exactly one tab doing the work | nothing at all |

## A leader

This is the part worth the package. Exactly one tab should poll, hold the
socket, or raise the notification — and when that tab closes, another must pick
it up without being told.

```dart
tabs.presence.listen((p) {
  if (p.isLeader) {
    socket.connect();
  } else {
    socket.disconnect();
  }
});
```

The oldest tab leads, with the id as a tiebreak. That second part matters more
than it looks: two tabs opened in the same microsecond would otherwise each
conclude the other should lead, or both lead. Comparing ids makes the ordering
total, so every tab reaches the same answer without further negotiation.

A tab that closes says goodbye, so the others react at once rather than waiting
out a timeout. A tab that crashes says nothing, so it is dropped after three
missed heartbeats.

## Presence

```dart
final p = tabs.current;
p.count;     // how many tabs are open
p.tabs;      // their ids, including this one
p.leader;    // whose turn it is, or null while an election settles
p.isLeader;  // whether that is you
```

`presence` emits the current state on subscription, so a listener knows where
it stands immediately rather than after the next change.

## Messages

```dart
tabs.send({'cart': items.length});
tabs.messages.listen((m) => print('from ${m.from}: ${m.data}'));
```

A tab never receives its own messages — the sender already knows what it sent.

## Off the web

The package compiles everywhere. On mobile and desktop there is exactly one
instance of your app, so it reports one tab and is always the leader.

That is the correct answer rather than a degraded one, and it is deliberate: it
means the code above runs unchanged on every platform, with no `if (kIsWeb)`
wrapped around your leader logic.

## Verified

Two `BroadcastChannel` objects with the same name see each other even within
one document, so the multi-tab behaviour is exercised for real rather than
mocked. `flutter test --platform chrome` covers four tabs agreeing on a single
leader, the oldest tab winning, leadership passing when the leader closes,
tabs discovering and losing each other, and a tab not hearing its own
messages. The single-instance path is tested on the VM.

## License

MIT © K M Shahriar Hossain
