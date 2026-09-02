import 'dart:typed_data';

import 'types.dart';

/// A file the user granted access to. Never constructed off the web.
class FileHandle {
  const FileHandle._();

  /// The file's name.
  String get name => throw _off();

  /// Reads the whole file.
  Future<Uint8List> readBytes() => throw _off();

  /// Reads the whole file as text.
  Future<String> readText() => throw _off();

  /// Overwrites the file in place.
  Future<void> writeBytes(Uint8List bytes) => throw _off();

  /// Overwrites the file in place with text.
  Future<void> writeText(String text) => throw _off();

  /// Current permission, without prompting.
  Future<FilePermission> permission({bool write = false}) => throw _off();

  /// Prompts for permission. Needs a user gesture.
  Future<FilePermission> requestPermission({bool write = false}) =>
      throw _off();
}

/// A directory the user granted access to. Never constructed off the web.
class DirectoryHandle {
  const DirectoryHandle._();

  /// The directory's name.
  String get name => throw _off();

  /// What the directory contains.
  Future<List<DirectoryEntry>> list() => throw _off();

  /// Opens a file inside this directory.
  Future<FileHandle> file(String name, {bool create = false}) => throw _off();

  /// Opens a subdirectory.
  Future<DirectoryHandle> directory(String name, {bool create = false}) =>
      throw _off();

  /// Deletes an entry.
  Future<void> remove(String name, {bool recursive = false}) => throw _off();

  /// Current permission, without prompting.
  Future<FilePermission> permission({bool write = false}) => throw _off();

  /// Prompts for permission. Needs a user gesture.
  Future<FilePermission> requestPermission({bool write = false}) =>
      throw _off();
}

/// The File System Access API, which does not exist off the web.
class FileSystemAccess {
  const FileSystemAccess._();

  /// Always [FileSystemAccessSupport.none] here.
  static FileSystemAccessSupport get support => FileSystemAccessSupport.none;

  /// Always false here.
  static bool get isSupported => false;

  /// Throws [UnsupportedByBrowserException].
  static Future<List<FileHandle>> openFiles({
    bool multiple = false,
    List<FilePickerType> types = const <FilePickerType>[],
    bool excludeAcceptAllOption = false,
  }) =>
      throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<FileHandle?> saveFile({
    String? suggestedName,
    List<FilePickerType> types = const <FilePickerType>[],
  }) =>
      throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<DirectoryHandle?> openDirectory({bool write = false}) =>
      throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<DirectoryHandle> originPrivateDirectory() => throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<void> remember(String key, Object handle) => throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<FileHandle?> recallFile(String key) => throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<DirectoryHandle?> recallDirectory(String key) => throw _off();

  /// Throws [UnsupportedByBrowserException].
  static Future<void> forget(String key) => throw _off();
}

UnsupportedByBrowserException _off() => const UnsupportedByBrowserException(
      'The File System Access API only exists on the web. Check '
      'FileSystemAccess.isSupported before calling this.',
    );
