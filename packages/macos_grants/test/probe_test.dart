// The Full Disk Access read, tested without a Mac, a home directory or a
// grant — the decisions are the part that can be wrong.
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_grants/macos_grants.dart';

/// A filesystem that exists only in this test.
class FakeFs implements ProbeFileSystem {
  FakeFs({
    this.home = '/Users/test',
    Set<String>? present,
    Set<String>? readable,
  })  : present = present ?? <String>{},
        readable = readable ?? <String>{};

  @override
  final String? home;

  /// Paths that exist. Anything not here is missing.
  final Set<String> present;

  /// Of those, the ones that open. The rest throw, as a protected path does.
  final Set<String> readable;

  final List<String> probed = <String>[];

  @override
  bool exists(String path) => present.contains(path);

  @override
  void probe(String path) {
    probed.add(path);
    if (!readable.contains(path)) {
      throw const FileSystemProbeDenied();
    }
  }
}

class FileSystemProbeDenied implements Exception {
  const FileSystemProbeDenied();
}

void main() {
  const List<String> paths = <String>['/abs/one', '~/two', '~/three'];

  test('a readable probe proves the grant', () {
    final FakeFs fs = FakeFs(
      present: <String>{'/abs/one'},
      readable: <String>{'/abs/one'},
    );
    expect(readFullDiskAccess(fs: fs, paths: paths), GrantStatus.granted);
  });

  test('a path that exists and refuses means denied', () {
    final FakeFs fs = FakeFs(present: <String>{'/abs/one'});
    expect(readFullDiskAccess(fs: fs, paths: paths), GrantStatus.denied);
  });

  test('nothing to probe is unknown, not denied', () {
    // A sandboxed app, or a Mac with no Mail and no Safari bookmarks. Saying
    // "denied" here sends the user to fix a permission that is already on.
    expect(readFullDiskAccess(fs: FakeFs(), paths: paths), GrantStatus.unknown);
  });

  test('every path is tried, not just the first', () {
    // The bug this replaced: judging from one probe reported denied whenever
    // that particular file happened to be missing or unreadable.
    final FakeFs fs = FakeFs(
      present: <String>{'/abs/one', '/Users/test/three'},
      readable: <String>{'/Users/test/three'},
    );
    expect(readFullDiskAccess(fs: fs, paths: paths), GrantStatus.granted);
    expect(fs.probed, <String>['/abs/one', '/Users/test/three']);
  });

  test('~ is expanded against home', () {
    final FakeFs fs = FakeFs(
      present: <String>{'/Users/test/two'},
      readable: <String>{'/Users/test/two'},
    );
    expect(readFullDiskAccess(fs: fs, paths: paths), GrantStatus.granted);
    expect(fs.probed.single, '/Users/test/two');
  });

  test('no home means the ~ paths are skipped, not guessed at', () {
    final FakeFs fs = FakeFs(
      home: null,
      present: <String>{'/abs/one', '/Users/test/two'},
      readable: <String>{'/Users/test/two'},
    );
    expect(readFullDiskAccess(fs: fs, paths: paths), GrantStatus.denied);
    expect(fs.probed, <String>['/abs/one']);
  });

  test('the shipped probe list covers more than one app', () {
    // If they all lived under ~/Library/Safari, a Mac without Safari data
    // would read as unknown forever.
    expect(kFullDiskAccessProbes.length, greaterThan(3));
    expect(
      kFullDiskAccessProbes.where((String p) => p.contains('TCC.db')).length,
      greaterThanOrEqualTo(1),
    );
  });
}
