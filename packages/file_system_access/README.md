# file_system_access

Real files on Flutter Web.

```dart
final file = await FileSystemAccess.saveFile(suggestedName: 'notes.txt');
await file?.writeText('saved into the file the user picked');

// Later, after a full page reload:
final again = await FileSystemAccess.recallFile('last-document');
print(await again?.readText());   // the same file, still there
```

## The problem

On Flutter Web, "Save" means "download another copy". The user picks
`notes.txt`, you write it, and their Downloads folder gains `notes (1).txt`,
then `notes (2).txt`. There is no way to write back into the file they opened,
and no way to find it again after a reload.

The File System Access API fixes both, and Flutter has no binding for it.
`package:web` ships the handle types but not the pickers — they appear only in
its doc comments — and neither permissions nor directory iteration.

## Saving in place

```dart
final files = await FileSystemAccess.openFiles(
  types: [FilePickerType.mime('text/plain', ['.txt', '.md'])],
);
final file = files.first;

final body = await file.readText();
await file.writeText('$body\n\nedited');   // same file, no second copy
```

Cancelling a picker is not an error — `openFiles` returns an empty list and
`saveFile` returns null, because the user changing their mind is not an
exceptional condition.

## Coming back to the same file

Handles are structured cloneable, so they can be kept in IndexedDB and taken
out on the next visit. This is the part that is genuinely hard without the API:

```dart
await FileSystemAccess.remember('last-document', file);

// next visit
final file = await FileSystemAccess.recallFile('last-document');
if (await file?.permission(write: true) != FilePermission.granted) {
  await file?.requestPermission(write: true);   // needs a user gesture
}
```

The browser may still confirm write access on a new visit. That is its
decision, not this package's, and `permission` tells you which state you are in
before you try.

## Ask what the browser has

```dart
final s = FileSystemAccess.support;
s.openPicker;      // Chrome, Edge
s.savePicker;
s.directoryPicker;
s.originPrivate;   // far more widely available
```

Four questions rather than one boolean, because the answers really do differ:
Safari has the origin-private file system and no pickers at all. Code that
checks a single flag will show a Save button that cannot work.

## Directories

```dart
final dir = await FileSystemAccess.openDirectory(write: true);
for (final entry in await dir!.list()) {
  print('${entry.name} ${entry.isDirectory ? "dir" : "file"}');
}
await dir.file('report.txt', create: true);
await dir.remove('old.txt');
```

## Private storage, no prompt

```dart
final root = await FileSystemAccess.originPrivateDirectory();
final scratch = await root.file('cache.bin', create: true);
```

The origin-private file system needs no picker and no permission, and is
supported far more widely than the pickers. It is invisible to the user, so use
it for scratch data rather than for anything they should be able to find on
disk.

## Off the web

The package compiles everywhere. On mobile and desktop `isSupported` is false
and every call throws `UnsupportedByBrowserException` with a message pointing
at the check you should have made — so an app that also targets web can depend
on it without conditional imports of its own.

## Verified

The web path is tested in a real browser, not mocked: `flutter test --platform
chrome` covers byte-for-byte round trips, non-ASCII text, truncation on
overwrite, directory listing, error paths, and storing a handle in IndexedDB
and reading the file back through it. The stub path is tested on the VM.

## License

MIT © K M Shahriar Hossain
