@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:file_system_access/file_system_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('support detection', () {
    test('reports each capability separately', () {
      final FileSystemAccessSupport s = FileSystemAccess.support;
      // ignore: avoid_print
      print('  $s');
      expect(s, isA<FileSystemAccessSupport>());
      // The origin-private file system is far more widely available than the
      // pickers, which is the whole reason these are asked apart.
      expect(
        s.originPrivate,
        isTrue,
        reason: 'headless Chrome should have OPFS',
      );
    });

    test('anyPicker agrees with the individual flags', () {
      final FileSystemAccessSupport s = FileSystemAccess.support;
      expect(s.anyPicker, s.openPicker || s.savePicker || s.directoryPicker);
    });
  });

  group('origin-private file system', () {
    test('writes a file and reads it back byte for byte', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final FileHandle f = await root.file('probe.bin', create: true);
      final Uint8List payload = Uint8List.fromList(
        List<int>.generate(512, (int i) => i % 256),
      );

      await f.writeBytes(payload);
      final Uint8List back = await f.readBytes();

      expect(back.length, payload.length);
      expect(back, orderedEquals(payload));
      await root.remove('probe.bin');
    });

    test('round-trips text, including characters outside ASCII', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final FileHandle f = await root.file('probe.txt', create: true);
      const String text = 'a fox — 狐 — reading a map';

      await f.writeText(text);
      expect(await f.readText(), text);
      await root.remove('probe.txt');
    });

    test('overwriting replaces rather than appends', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final FileHandle f = await root.file('twice.txt', create: true);

      await f.writeText('the first, much longer, contents');
      await f.writeText('short');

      // A writable stream that was not truncated would leave the tail behind.
      expect(await f.readText(), 'short');
      await root.remove('twice.txt');
    });

    test('lists what a directory contains', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final DirectoryHandle dir = await root.directory('probe', create: true);
      await dir.file('one.txt', create: true);
      await dir.file('two.txt', create: true);
      await dir.directory('nested', create: true);

      final List<DirectoryEntry> entries = await dir.list();
      final Set<String> names =
          entries.map((DirectoryEntry e) => e.name).toSet();
      expect(names, containsAll(<String>['one.txt', 'two.txt', 'nested']));
      expect(
        entries
            .firstWhere((DirectoryEntry e) => e.name == 'nested')
            .isDirectory,
        isTrue,
      );
      expect(
        entries.firstWhere((DirectoryEntry e) => e.name == 'one.txt').isFile,
        isTrue,
      );
      await root.remove('probe', recursive: true);
    });

    test('opening a missing file without create fails cleanly', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      await expectLater(
        root.file('does-not-exist.txt'),
        throwsA(isA<FileSystemFailure>()),
      );
    });

    test('removing a missing entry fails cleanly', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      await expectLater(
        root.remove('never-existed.txt'),
        throwsA(isA<FileSystemFailure>()),
      );
    });
  });

  group('remembering handles across reloads', () {
    test('a handle put away can be taken out again', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final FileHandle f = await root.file('kept.txt', create: true);
      await f.writeText('still here');

      await FileSystemAccess.remember('probe-key', f);
      final FileHandle? again = await FileSystemAccess.recallFile('probe-key');

      expect(again, isNotNull);
      expect(again!.name, 'kept.txt');
      // The point of persisting a handle is that the file is still reachable.
      expect(await again.readText(), 'still here');

      await FileSystemAccess.forget('probe-key');
      expect(await FileSystemAccess.recallFile('probe-key'), isNull);
      await root.remove('kept.txt');
    });

    test('a directory handle survives too', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final DirectoryHandle dir = await root.directory(
        'kept-dir',
        create: true,
      );

      await FileSystemAccess.remember('probe-dir', dir);
      final DirectoryHandle? again = await FileSystemAccess.recallDirectory(
        'probe-dir',
      );

      expect(again, isNotNull);
      expect(again!.name, 'kept-dir');

      await FileSystemAccess.forget('probe-dir');
      await root.remove('kept-dir', recursive: true);
    });

    test('recalling an unknown key is null, not an error', () async {
      expect(await FileSystemAccess.recallFile('never-stored'), isNull);
      expect(await FileSystemAccess.recallDirectory('never-stored'), isNull);
    });

    test('remembering something that is not a handle is rejected', () async {
      await expectLater(
        FileSystemAccess.remember('bad', 'just a string'),
        throwsArgumentError,
      );
    });
  });

  group('permissions', () {
    test('an origin-private handle needs no prompt', () async {
      final DirectoryHandle root =
          await FileSystemAccess.originPrivateDirectory();
      final FilePermission p = await root.permission();
      // ignore: avoid_print
      print('  origin-private read permission: ${p.name}');
      expect(p, isA<FilePermission>());
    });
  });
}
