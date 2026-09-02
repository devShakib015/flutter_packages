import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'interop.dart';
import 'types.dart';

/// A file the user granted access to.
///
/// Unlike a download, this is a live handle onto a real file: writing to it
/// changes the file the user picked, in place, with no second copy in their
/// Downloads folder. It also survives a page reload if you
/// [FileSystemAccess.remember] it.
class FileHandle {
  /// Wraps a browser handle.
  FileHandle.fromNative(this.native);

  /// The underlying browser object. Exposed so a handle can be stored or
  /// compared; there is rarely a reason to touch it.
  final web.FileSystemFileHandle native;

  /// The file's name, as the user sees it.
  String get name => (native as FsHandle).name;

  /// Reads the whole file.
  Future<Uint8List> readBytes() async {
    try {
      final web.File file = await native.getFile().toDart;
      final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    } catch (e) {
      _fail(e, 'Reading "$name"');
    }
  }

  /// Reads the whole file as UTF-8 text.
  Future<String> readText() async {
    try {
      final web.File file = await native.getFile().toDart;
      return (await file.text().toDart).toDart;
    } catch (e) {
      _fail(e, 'Reading "$name"');
    }
  }

  /// Overwrites the file in place.
  ///
  /// This is the part a download cannot do. The user picked this file once;
  /// saving again does not ask them, and does not leave a `document (3).txt`
  /// behind.
  Future<void> writeBytes(Uint8List bytes) async =>
      _writeThrough(await _open(), bytes.toJS);

  /// Overwrites the file in place with UTF-8 text.
  Future<void> writeText(String text) async =>
      _writeThrough(await _open(), text.toJS);

  /// Writes and closes, keeping whichever failure came first.
  ///
  /// Nothing reaches disk until the stream closes, so the close has to happen
  /// even when the write threw — but doing it in a `finally` meant a failing
  /// close overwrote the real error with a bare `TypeError` from the closed
  /// stream, and the caller never learned that the disk was full or the
  /// permission had lapsed.
  Future<void> _writeThrough(
    web.FileSystemWritableFileStream stream,
    JSAny data,
  ) async {
    Object? failure;
    try {
      await stream.write(data).toDart;
    } catch (e) {
      failure = e;
    }
    try {
      await stream.close().toDart;
    } catch (e) {
      failure ??= e;
    }
    if (failure != null) _fail(failure, 'Writing to "$name"');
  }

  /// Opens the writable stream, translating the browser's refusal.
  ///
  /// A denied write surfaces as NotAllowedError, which says nothing useful on
  /// its own. Callers want to know it was permission — usually so they can
  /// prompt from a user gesture and try again.
  Future<web.FileSystemWritableFileStream> _open() async {
    try {
      return await native.createWritable().toDart;
    } catch (e) {
      if (_isNotAllowed(e)) {
        throw PermissionDeniedException(
          'Write access to "$name" was refused. Call requestPermission('
          'write: true) from a user gesture, then try again.',
        );
      }
      throw FileSystemFailure('Could not open "$name" for writing: $e');
    }
  }

  /// Current permission, without prompting.
  Future<FilePermission> permission({bool write = false}) =>
      _query(native as FsHandle, write: write, prompt: false);

  /// Prompts for permission.
  ///
  /// The browser only allows this during a user gesture — call it from a tap
  /// handler, not from `initState`.
  Future<FilePermission> requestPermission({bool write = false}) =>
      _query(native as FsHandle, write: write, prompt: true);

  @override
  String toString() => 'FileHandle($name)';
}

/// A directory the user granted access to.
class DirectoryHandle {
  /// Wraps a browser handle.
  DirectoryHandle.fromNative(this.native);

  /// The underlying browser object.
  final web.FileSystemDirectoryHandle native;

  /// The directory's name.
  String get name => (native as FsHandle).name;

  /// What the directory contains, one level deep.
  Future<List<DirectoryEntry>> list() async {
    final JSAny? iterable = (native as JSObject).callMethod<JSAny?>(
      'values'.toJS,
    );
    if (iterable == null) return const <DirectoryEntry>[];
    final AsyncIterator iterator = iterable as AsyncIterator;
    final List<DirectoryEntry> out = <DirectoryEntry>[];
    while (true) {
      final IterResult step = await iterator.next().toDart;
      if (step.done) break;
      final JSAny? value = step.value;
      if (value == null) continue;
      final FsHandle handle = value as FsHandle;
      out.add(
        DirectoryEntry(
          name: handle.name,
          isDirectory: handle.kind == 'directory',
        ),
      );
    }
    return out;
  }

  /// Opens a file inside this directory, optionally creating it.
  Future<FileHandle> file(String name, {bool create = false}) async {
    try {
      final web.FileSystemFileHandle handle = await native
          .getFileHandle(name, web.FileSystemGetFileOptions(create: create))
          .toDart;
      return FileHandle.fromNative(handle);
    } catch (e) {
      throw FileSystemFailure('Could not open "$name": $e');
    }
  }

  /// Opens a subdirectory, optionally creating it.
  Future<DirectoryHandle> directory(String name, {bool create = false}) async {
    try {
      final web.FileSystemDirectoryHandle handle = await native
          .getDirectoryHandle(
            name,
            web.FileSystemGetDirectoryOptions(create: create),
          )
          .toDart;
      return DirectoryHandle.fromNative(handle);
    } catch (e) {
      throw FileSystemFailure('Could not open directory "$name": $e');
    }
  }

  /// Deletes an entry from this directory.
  Future<void> remove(String name, {bool recursive = false}) async {
    try {
      await native
          .removeEntry(name, web.FileSystemRemoveOptions(recursive: recursive))
          .toDart;
    } catch (e) {
      throw FileSystemFailure('Could not remove "$name": $e');
    }
  }

  /// Current permission, without prompting.
  Future<FilePermission> permission({bool write = false}) =>
      _query(native as FsHandle, write: write, prompt: false);

  /// Prompts for permission. Needs a user gesture.
  Future<FilePermission> requestPermission({bool write = false}) =>
      _query(native as FsHandle, write: write, prompt: true);

  @override
  String toString() => 'DirectoryHandle($name)';
}

Future<FilePermission> _query(
  FsHandle handle, {
  required bool write,
  required bool prompt,
}) async {
  final JSObject descriptor = JSObject()
    ..setProperty('mode'.toJS, (write ? 'readwrite' : 'read').toJS);
  try {
    final JSString state =
        await (prompt
                ? handle.requestPermission(descriptor)
                : handle.queryPermission(descriptor))
            .toDart;
    return switch (state.toDart) {
      'granted' => FilePermission.granted,
      'denied' => FilePermission.denied,
      _ => FilePermission.prompt,
    };
  } catch (_) {
    // Some browsers have the handles but not the permission methods. Treating
    // that as "must ask" is the safe reading.
    return FilePermission.prompt;
  }
}

/// The File System Access API.
class FileSystemAccess {
  const FileSystemAccess._();

  /// What this browser can do, asked feature by feature.
  static FileSystemAccessSupport get support => FileSystemAccessSupport(
    openPicker: windowHas('showOpenFilePicker'),
    savePicker: windowHas('showSaveFilePicker'),
    directoryPicker: windowHas('showDirectoryPicker'),
    originPrivate: _hasOriginPrivate(),
  );

  /// Whether any picker is available.
  static bool get isSupported => support.anyPicker;

  static bool _hasOriginPrivate() {
    try {
      final JSObject? storage = web.window.navigator.getProperty<JSObject?>(
        'storage'.toJS,
      );
      return storage != null &&
          storage.getProperty<JSAny?>('getDirectory'.toJS) != null;
    } catch (_) {
      return false;
    }
  }

  /// Asks the user to choose files to open.
  ///
  /// Returns an empty list if they cancel — cancelling is not an error, and
  /// making callers catch for it would be tiresome.
  static Future<List<FileHandle>> openFiles({
    bool multiple = false,
    List<FilePickerType> types = const <FilePickerType>[],
    bool excludeAcceptAllOption = false,
  }) async {
    if (!windowHas('showOpenFilePicker')) {
      throw const UnsupportedByBrowserException(
        'This browser has no showOpenFilePicker. Check '
        'FileSystemAccess.support before offering this.',
      );
    }
    final JSObject options = JSObject()
      ..setProperty('multiple'.toJS, multiple.toJS)
      ..setProperty('excludeAcceptAllOption'.toJS, excludeAcceptAllOption.toJS);
    if (types.isNotEmpty) options.setProperty('types'.toJS, _types(types));
    try {
      final JSArray<web.FileSystemFileHandle> handles = await fsWindow
          .showOpenFilePicker(options)
          .toDart;
      return handles.toDart.map(FileHandle.fromNative).toList(growable: false);
    } catch (e) {
      if (_isAbort(e)) return const <FileHandle>[];
      throw FileSystemFailure('Could not open files: $e');
    }
  }

  /// Asks the user where to save, and returns a handle that can be written to
  /// repeatedly without asking again.
  ///
  /// Returns null if they cancel.
  static Future<FileHandle?> saveFile({
    String? suggestedName,
    List<FilePickerType> types = const <FilePickerType>[],
  }) async {
    if (!windowHas('showSaveFilePicker')) {
      throw const UnsupportedByBrowserException(
        'This browser has no showSaveFilePicker. Check '
        'FileSystemAccess.support before offering a Save button.',
      );
    }
    final JSObject options = JSObject();
    if (suggestedName != null) {
      options.setProperty('suggestedName'.toJS, suggestedName.toJS);
    }
    if (types.isNotEmpty) options.setProperty('types'.toJS, _types(types));
    try {
      final web.FileSystemFileHandle handle = await fsWindow
          .showSaveFilePicker(options)
          .toDart;
      return FileHandle.fromNative(handle);
    } catch (e) {
      if (_isAbort(e)) return null;
      throw FileSystemFailure('Could not save: $e');
    }
  }

  /// Asks the user to grant a whole directory. Returns null if they cancel.
  static Future<DirectoryHandle?> openDirectory({bool write = false}) async {
    if (!windowHas('showDirectoryPicker')) {
      throw const UnsupportedByBrowserException(
        'This browser has no showDirectoryPicker.',
      );
    }
    final JSObject options = JSObject()
      ..setProperty('mode'.toJS, (write ? 'readwrite' : 'read').toJS);
    try {
      final web.FileSystemDirectoryHandle handle = await fsWindow
          .showDirectoryPicker(options)
          .toDart;
      return DirectoryHandle.fromNative(handle);
    } catch (e) {
      if (_isAbort(e)) return null;
      throw FileSystemFailure('Could not open a directory: $e');
    }
  }

  /// The origin-private file system: private storage for this site, with no
  /// picker and no permission prompt.
  ///
  /// Far more widely supported than the pickers, and invisible to the user —
  /// use it for scratch data rather than for anything they should be able to
  /// find on their disk.
  static Future<DirectoryHandle> originPrivateDirectory() async {
    if (!_hasOriginPrivate()) {
      throw const UnsupportedByBrowserException(
        'This browser has no origin-private file system.',
      );
    }
    final web.FileSystemDirectoryHandle root = await web
        .window
        .navigator
        .storage
        .getDirectory()
        .toDart;
    return DirectoryHandle.fromNative(root);
  }

  // ------------------------------------------------------------ persistence

  static const String _dbName = 'file_system_access';
  static const String _storeName = 'handles';

  /// Remembers a handle under [key], so the same file can be reopened after a
  /// reload without asking the user again.
  ///
  /// This is the part that makes the API worth having. Handles are structured
  /// cloneable, so they can live in IndexedDB; the grant survives with them,
  /// though the browser may still ask to confirm write access on a new visit.
  static Future<void> remember(String key, Object handle) async {
    final JSAny native = switch (handle) {
      FileHandle() => handle.native,
      DirectoryHandle() => handle.native,
      _ => throw ArgumentError.value(
        handle,
        'handle',
        'expected a FileHandle or DirectoryHandle',
      ),
    };
    final web.IDBDatabase db = await _open();
    final web.IDBTransaction tx = db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).put(native, key.toJS);
    await _done(tx);
    db.close();
  }

  /// Reopens a file remembered under [key], or null if there is none.
  static Future<FileHandle?> recallFile(String key) async {
    final JSAny? value = await _read(key);
    if (value == null) return null;
    // A handle knows what it is, and the cast alone does not: these are
    // extension types over the same JS object, so casting a directory handle
    // to a file handle succeeds and only fails much later, somewhere
    // confusing.
    if ((value as FsHandle).kind != 'file') return null;
    return FileHandle.fromNative(value as web.FileSystemFileHandle);
  }

  /// Reopens a directory remembered under [key], or null if there is none.
  static Future<DirectoryHandle?> recallDirectory(String key) async {
    final JSAny? value = await _read(key);
    if (value == null) return null;
    if ((value as FsHandle).kind != 'directory') return null;
    return DirectoryHandle.fromNative(value as web.FileSystemDirectoryHandle);
  }

  /// Forgets the handle stored under [key].
  static Future<void> forget(String key) async {
    final web.IDBDatabase db = await _open();
    final web.IDBTransaction tx = db.transaction(_storeName.toJS, 'readwrite');
    tx.objectStore(_storeName).delete(key.toJS);
    await _done(tx);
    db.close();
  }

  static Future<JSAny?> _read(String key) async {
    final web.IDBDatabase db = await _open();
    final web.IDBTransaction tx = db.transaction(_storeName.toJS, 'readonly');
    final web.IDBRequest request = tx.objectStore(_storeName).get(key.toJS);
    final Completer<JSAny?> done = Completer<JSAny?>();
    request.onsuccess = (web.Event _) {
      done.complete(request.result);
    }.toJS;
    request.onerror = (web.Event _) {
      done.complete(null);
    }.toJS;
    final JSAny? value = await done.future;
    db.close();
    return value;
  }

  static Future<web.IDBDatabase> _open() {
    final Completer<web.IDBDatabase> done = Completer<web.IDBDatabase>();
    final web.IDBOpenDBRequest request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = (web.Event _) {
      final web.IDBDatabase db = request.result! as web.IDBDatabase;
      if (!db.objectStoreNames.contains(_storeName)) {
        db.createObjectStore(_storeName);
      }
    }.toJS;
    request.onsuccess = (web.Event _) {
      done.complete(request.result! as web.IDBDatabase);
    }.toJS;
    request.onerror = (web.Event _) {
      done.completeError(
        const FileSystemFailure('Could not open the handle store.'),
      );
    }.toJS;
    return done.future;
  }

  static Future<void> _done(web.IDBTransaction tx) {
    final Completer<void> done = Completer<void>();
    tx.oncomplete = (web.Event _) {
      if (!done.isCompleted) done.complete();
    }.toJS;
    tx.onerror = (web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
          const FileSystemFailure('The handle store rejected the write.'),
        );
      }
    }.toJS;
    // An aborted transaction fires neither of the above — a quota failure or
    // the tab going away mid-write left remember() and forget() awaiting a
    // future nobody would ever complete.
    tx.onabort = (web.Event _) {
      if (!done.isCompleted) {
        done.completeError(
          const FileSystemFailure('The handle store transaction was aborted.'),
        );
      }
    }.toJS;
    return done.future;
  }

  static JSArray<JSObject> _types(List<FilePickerType> types) {
    return types
        .map((FilePickerType t) {
          final JSObject accept = JSObject();
          t.accept.forEach((String mime, List<String> extensions) {
            accept.setProperty(
              mime.toJS,
              extensions.map((String e) => e.toJS).toList().toJS,
            );
          });
          return JSObject()
            ..setProperty('description'.toJS, t.description.toJS)
            ..setProperty('accept'.toJS, accept);
        })
        .toList()
        .toJS;
  }

  /// A cancelled picker throws AbortError, which is not a failure — the user
  /// simply changed their mind.
  static bool _isAbort(Object error) => error.toString().contains('AbortError');
}

/// Turns a browser rejection into this package's own exception type.
///
/// Every path that touches the File System Access API has to go through this.
/// A raw `DOMException` crossing into Dart is not catchable by
/// `on FileSystemAccessException`, which is the whole contract this package
/// offers — so an untranslated read looked like it could not fail at all and
/// then threw something nobody could catch.
Never _fail(Object error, String what) {
  if (_isNotAllowed(error)) {
    throw PermissionDeniedException(
      '$what was refused. Call requestPermission() from a user gesture, then '
      'try again.',
    );
  }
  throw FileSystemFailure('$what failed: $error');
}

/// Whether the browser refused for permission reasons.
bool _isNotAllowed(Object error) {
  final String text = error.toString();
  return text.contains('NotAllowedError') || text.contains('SecurityError');
}
