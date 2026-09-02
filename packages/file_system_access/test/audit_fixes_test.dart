@TestOn('browser')
library;

// Each test pins a defect found by the 2026-09-02 audit.
import 'package:file_system_access/file_system_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recalling the wrong kind gives null, not a wrong-typed handle',
    () async {
      // Shipped in 0.1.1: recallFile blind-cast whatever was stored. These are
      // extension types over the same JS object, so casting a directory handle
      // to a file handle succeeded and only blew up much later, somewhere with
      // no connection to the mistake.
      final dir = await FileSystemAccess.originPrivateDirectory();
      await FileSystemAccess.remember('audit-dir', dir);

      expect(await FileSystemAccess.recallDirectory('audit-dir'), isNotNull);
      expect(
        await FileSystemAccess.recallFile('audit-dir'),
        isNull,
        reason: 'a directory is not a file',
      );

      await FileSystemAccess.forget('audit-dir');
    },
  );

  test('a missing key is still null', () async {
    expect(await FileSystemAccess.recallFile('audit-nothing-here'), isNull);
    expect(
      await FileSystemAccess.recallDirectory('audit-nothing-here'),
      isNull,
    );
  });

  test('remember and forget round-trip through the handle store', () async {
    // Also proves _done resolves: before the fix an aborted transaction fired
    // neither oncomplete nor onerror and these awaited forever.
    final dir = await FileSystemAccess.originPrivateDirectory();
    final file = await dir.file('audit-roundtrip.txt', create: true);
    await file.writeText('kept');

    await FileSystemAccess.remember('audit-file', file);
    final again = await FileSystemAccess.recallFile('audit-file');
    expect(again, isNotNull);
    expect(await again!.readText(), 'kept');

    await FileSystemAccess.forget('audit-file');
    expect(await FileSystemAccess.recallFile('audit-file'), isNull);

    await dir.remove('audit-roundtrip.txt');
  });

  test('a read failure is catchable as this package own exception', () async {
    // Shipped in 0.1.1: readBytes/readText translated nothing, so a failed
    // read threw a raw JS DOMException that `on FileSystemAccessException`
    // could not catch — the entire error contract the package advertises.
    final dir = await FileSystemAccess.originPrivateDirectory();
    final file = await dir.file('audit-vanishing.txt', create: true);
    await file.writeText('here');
    await dir.remove('audit-vanishing.txt');

    // The handle now points at nothing.
    Object? caught;
    try {
      await file.readText();
    } catch (e) {
      caught = e;
    }
    expect(caught, isNotNull, reason: 'reading a removed file must fail');
    expect(
      caught,
      isA<FileSystemAccessException>(),
      reason: 'and must be catchable by the type the README promises',
    );
  });
}
