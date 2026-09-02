## 0.2.1

No code changes. This release exists because the package was almost impossible
to install.

`sdk: ^3.13.0` meant Dart 3.13, which only ships with **Flutter 3.47** —
released three weeks ago. Anyone on an older SDK hit a version-solve failure
before they could try it. The floor is now `^3.5.0` / Flutter 3.24, and it is
tested: the library resolves and type-checks against Flutter 3.16.9 / Dart
3.2.6, so the declared range is narrower than the verified one.

## 0.2.0

An audit of every package in this repo found five defects here, one of them in
the first snippet of the README.

### Fixed

- **A failed read threw something you could not catch.** `readBytes`,
  `readText` and the directory paths translated nothing, so a browser
  rejection crossed into Dart as a raw `DOMException` — invisible to
  `on FileSystemAccessException`, which is the error contract this package
  exists to provide. Every browser rejection now goes through one translator.
- **The README's flagship snippet printed null.** It recalled
  `'last-document'` without ever remembering it. The `remember` call is there
  now.
- **A failing close replaced the real write error.** `await stream.close()` sat
  in a `finally`, so when a write failed the close failed too and its bare
  `TypeError` was what surfaced — the caller never learned the disk was full or
  the permission had lapsed. Whichever failure came first is kept.
- **Recalling the wrong kind returned a wrong-typed handle.** File and
  directory handles are extension types over the same JS object, so the cast
  always succeeded and only broke later somewhere unrelated. Both now check
  `kind` and return null on a mismatch.
- **An aborted IndexedDB transaction hung forever.** `_done` listened for
  complete and error but not abort, so a quota failure or a tab closing
  mid-write left `remember` and `forget` awaiting a future nobody would
  complete.

## 0.1.1

- `PermissionDeniedException` is now actually thrown. It was exported from
  0.1.0 but nothing raised it, so a caller could write a `catch` that could
  never fire. A refused write surfaces as the browser's `NotAllowedError`,
  which says nothing useful on its own; it is now translated, and the message
  says to call `requestPermission(write: true)` from a user gesture.

## 0.1.0

Initial release: the File System Access API for Flutter Web.

- `openFiles`, `saveFile` and `openDirectory` wrap the three pickers, which
  `package:web` mentions in its doc comments but does not bind.
- `FileHandle.writeText`/`writeBytes` write back into the file the user picked,
  in place — not a second copy in their Downloads folder.
- `remember` / `recallFile` / `recallDirectory` keep a handle in IndexedDB, so
  the same file is reachable after a full page reload.
- `DirectoryHandle` lists, opens and removes entries, with async iteration
  bound by hand since `package:web` does not expose it.
- `permission` and `requestPermission` report `granted`, `prompt` or `denied`
  rather than a boolean, because "must ask" is not the same as "refused".
- `FileSystemAccess.support` answers for each picker and the origin-private
  file system separately — Safari has the latter and none of the former.
- Off the web the package still compiles and reports everything unsupported.

Tested in a real browser via `flutter test --platform chrome`, including a
handle stored in IndexedDB and the file read back through it after recall.
