import 'dart:typed_data';

/// A file type offered in a picker.
///
/// The browser shows [description] in its filter dropdown, and only files
/// matching [accept] can be chosen — or, when saving, the extension it will
/// append.
class FilePickerType {
  /// Creates a file type filter.
  const FilePickerType({required this.description, required this.accept});

  /// Convenience for a single MIME type and its extensions.
  factory FilePickerType.mime(
    String mimeType,
    List<String> extensions, {
    String? description,
  }) => FilePickerType(
    description: description ?? mimeType,
    accept: <String, List<String>>{mimeType: extensions},
  );

  /// Shown in the browser's filter dropdown.
  final String description;

  /// MIME type to the extensions that satisfy it, e.g.
  /// `{'text/plain': ['.txt', '.md']}`.
  final Map<String, List<String>> accept;
}

/// Whether the page may read or write a handle without asking again.
enum FilePermission {
  /// Allowed. Reads and writes will not prompt.
  granted,

  /// The user must be asked. Asking requires a user gesture.
  prompt,

  /// Refused for this handle.
  denied,
}

/// What a directory contains.
class DirectoryEntry {
  /// Creates an entry.
  const DirectoryEntry({required this.name, required this.isDirectory});

  /// The entry's name within its parent.
  final String name;

  /// Whether this is a directory rather than a file.
  final bool isDirectory;

  /// Whether this is a file rather than a directory.
  bool get isFile => !isDirectory;

  @override
  String toString() => 'DirectoryEntry($name, ${isDirectory ? "dir" : "file"})';
}

/// Thrown when the browser cannot do what was asked.
sealed class FileSystemAccessException implements Exception {
  /// Creates an exception with a human-readable [message].
  const FileSystemAccessException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// This browser, or this platform, has no File System Access API.
///
/// Chrome and Edge have it; Firefox and Safari largely do not. Check
/// [FileSystemAccessSupport] before offering the feature rather than catching
/// this after the user has clicked something.
class UnsupportedByBrowserException extends FileSystemAccessException {
  /// Creates the exception.
  const UnsupportedByBrowserException(super.message);
}

/// The page does not have permission to read or write the handle.
class PermissionDeniedException extends FileSystemAccessException {
  /// Creates the exception.
  const PermissionDeniedException(super.message);
}

/// The operation failed for a reason the browser reported.
class FileSystemFailure extends FileSystemAccessException {
  /// Creates the exception.
  const FileSystemFailure(super.message);
}

/// What this browser can actually do.
///
/// The API arrived in pieces and is still not everywhere, so these are asked
/// separately. Safari, for instance, has the origin-private file system but no
/// pickers at all — code that assumes one boolean will offer a Save button
/// that cannot work.
class FileSystemAccessSupport {
  /// Creates a support report.
  const FileSystemAccessSupport({
    required this.openPicker,
    required this.savePicker,
    required this.directoryPicker,
    required this.originPrivate,
  });

  /// Nothing is available — a non-web platform, or a browser without any of it.
  static const FileSystemAccessSupport none = FileSystemAccessSupport(
    openPicker: false,
    savePicker: false,
    directoryPicker: false,
    originPrivate: false,
  );

  /// Whether the user can be asked to open files.
  final bool openPicker;

  /// Whether the user can be asked where to save.
  final bool savePicker;

  /// Whether the user can be asked to grant a whole directory.
  final bool directoryPicker;

  /// Whether the origin-private file system is available. This one needs no
  /// permission and no picker, and is far more widely supported.
  final bool originPrivate;

  /// Whether any picker at all is available.
  bool get anyPicker => openPicker || savePicker || directoryPicker;

  @override
  String toString() =>
      'FileSystemAccessSupport(open: $openPicker, save: $savePicker, '
      'directory: $directoryPicker, originPrivate: $originPrivate)';
}

/// Bytes plus the name they came from.
class NamedBytes {
  /// Creates a named byte payload.
  const NamedBytes({required this.name, required this.bytes});

  /// The file's name.
  final String name;

  /// Its contents.
  final Uint8List bytes;

  @override
  String toString() => 'NamedBytes($name, ${bytes.length} bytes)';
}
