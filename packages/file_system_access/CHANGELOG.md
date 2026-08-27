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
