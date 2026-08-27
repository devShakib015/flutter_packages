@TestOn('vm')
library;

import 'package:file_system_access/file_system_access.dart';
import 'package:flutter_test/flutter_test.dart';

/// Off the web there is no File System Access API at all. The package still
/// has to compile and answer honestly, so an app targeting mobile as well as
/// web can depend on it without conditional imports of its own.
void main() {
  group('off the web', () {
    test('reports nothing supported rather than pretending', () {
      expect(FileSystemAccess.isSupported, isFalse);
      final FileSystemAccessSupport s = FileSystemAccess.support;
      expect(s.openPicker, isFalse);
      expect(s.savePicker, isFalse);
      expect(s.directoryPicker, isFalse);
      expect(s.originPrivate, isFalse);
      expect(s.anyPicker, isFalse);
    });

    test('every entry point throws the same, explicable error', () {
      Matcher unsupported() => throwsA(isA<UnsupportedByBrowserException>());
      expect(FileSystemAccess.openFiles, unsupported());
      expect(FileSystemAccess.saveFile, unsupported());
      expect(FileSystemAccess.openDirectory, unsupported());
      expect(FileSystemAccess.originPrivateDirectory, unsupported());
      expect(() => FileSystemAccess.recallFile('k'), unsupported());
      expect(() => FileSystemAccess.recallDirectory('k'), unsupported());
      expect(() => FileSystemAccess.forget('k'), unsupported());
    });

    test('the error says what to check instead', () {
      try {
        FileSystemAccess.openFiles();
        fail('should have thrown');
      } on UnsupportedByBrowserException catch (e) {
        expect(e.message, contains('isSupported'));
      }
    });
  });

  group('types', () {
    test('a mime shorthand builds the accept map', () {
      final FilePickerType t = FilePickerType.mime('text/plain', <String>[
        '.txt',
        '.md',
      ]);
      expect(t.description, 'text/plain');
      expect(t.accept['text/plain'], <String>['.txt', '.md']);
    });

    test('a description overrides the mime type as the label', () {
      final FilePickerType t = FilePickerType.mime('application/json', <String>[
        '.json',
      ], description: 'Config files');
      expect(t.description, 'Config files');
    });

    test('a directory entry knows which it is', () {
      const DirectoryEntry d = DirectoryEntry(name: 'x', isDirectory: true);
      const DirectoryEntry f = DirectoryEntry(name: 'y', isDirectory: false);
      expect(d.isFile, isFalse);
      expect(f.isFile, isTrue);
    });

    test('the none report is entirely negative', () {
      expect(FileSystemAccessSupport.none.anyPicker, isFalse);
      expect(FileSystemAccessSupport.none.originPrivate, isFalse);
    });
  });
}
