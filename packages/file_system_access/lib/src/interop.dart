import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Bindings for the parts of the File System Access API that `package:web`
/// does not expose.
///
/// It has the handle types and the origin-private file system, but the three
/// pickers appear only in its doc comments, and permission querying and
/// directory iteration are absent entirely. Those are exactly the parts an app
/// needs, so they are declared here.
extension type FsWindow._(JSObject _) implements JSObject {
  /// Asks the user to choose one or more files to open.
  external JSPromise<JSArray<web.FileSystemFileHandle>> showOpenFilePicker(
    JSObject options,
  );

  /// Asks the user where to save, returning a writable handle.
  external JSPromise<web.FileSystemFileHandle> showSaveFilePicker(
    JSObject options,
  );

  /// Asks the user to grant access to a whole directory.
  external JSPromise<web.FileSystemDirectoryHandle> showDirectoryPicker(
    JSObject options,
  );
}

/// Permission and identity members present on every handle but absent from
/// `package:web`.
extension type FsHandle._(JSObject _) implements JSObject {
  /// Current permission, without prompting.
  external JSPromise<JSString> queryPermission(JSObject descriptor);

  /// Prompts for permission. Requires a user gesture.
  external JSPromise<JSString> requestPermission(JSObject descriptor);

  /// The entry's name.
  external String get name;

  /// Either `file` or `directory`.
  external String get kind;
}

/// One step of a JS async iterator.
extension type IterResult._(JSObject _) implements JSObject {
  /// Whether iteration has finished.
  external bool get done;

  /// The value produced by this step, absent once [done].
  external JSAny? get value;
}

/// The async iterator a directory handle's `values()` returns.
extension type AsyncIterator._(JSObject _) implements JSObject {
  /// Advances the iterator.
  external JSPromise<IterResult> next();
}

/// The window, seen as something that has the pickers.
@JS('window')
external FsWindow get fsWindow;

/// Whether `window` has [name].
///
/// This is how browser capability is decided here — asking whether the
/// function exists, rather than sniffing the user agent, or calling it and
/// catching, which would prompt the user.
bool windowHas(String name) =>
    (fsWindow as JSObject).getProperty<JSAny?>(name.toJS) != null;
