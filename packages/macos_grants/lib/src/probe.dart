/// Reading Full Disk Access the only way macOS allows: by trying.
library;

import 'dart:io';

/// What a privacy grant looks like from inside the app.
enum GrantStatus {
  /// The app can do the thing the grant protects.
  granted,

  /// The app is blocked.
  denied,

  /// It could not be determined. A sandboxed app, a Mac missing every probe
  /// path, or a check that could not run. Treat it as "ask the user", never
  /// as denied: telling someone to fix a permission they already gave is how
  /// an app ends up in a loop with no exit.
  unknown,
}

/// Paths macOS keeps behind the Full Disk Access switch.
///
/// There is no API for this grant — no request, no query — so the only honest
/// test is to open something it protects and see what happens. Several paths,
/// because they are Apple's to move and a Mac may legitimately be missing any
/// one of them; a single readable path proves the grant.
const List<String> kFullDiskAccessProbes = <String>[
  '/Library/Application Support/com.apple.TCC/TCC.db',
  '~/Library/Application Support/com.apple.TCC/TCC.db',
  '~/Library/Safari/Bookmarks.plist',
  '~/Library/Mail',
  '~/Library/Messages/chat.db',
  '~/Library/Cookies/Cookies.binarycookies',
  '~/Library/Application Support/AddressBook',
];

/// The filesystem, as this package needs it. Swappable so the decision logic
/// can be tested without a Mac, a home directory or a real grant.
abstract class ProbeFileSystem {
  /// Whether [path] exists at all, without following symlinks.
  bool exists(String path);

  /// Read one byte, or list one entry. Throws when the path is protected.
  void probe(String path);

  /// The user's home directory, or null when there isn't one.
  String? get home;
}

/// The real thing.
class SystemProbeFileSystem implements ProbeFileSystem {
  /// The default, reading the real filesystem.
  const SystemProbeFileSystem();

  @override
  String? get home => Platform.environment['HOME'];

  @override
  bool exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  void probe(String path) {
    final FileSystemEntityType type =
        FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      // One entry is enough: listing a protected directory throws on the
      // first read, not at the end.
      Directory(path).listSync(followLinks: false).take(1).toList();
    } else {
      final RandomAccessFile handle = File(path).openSync();
      handle.closeSync();
    }
  }
}

/// Reads Full Disk Access by probing the paths it protects.
///
/// Every candidate is tried rather than judging from the first: a Mac with no
/// Mail and no Safari bookmarks would otherwise report denied when nothing is
/// wrong. Any readable probe proves the grant; probes that exist and refuse
/// prove the opposite; nothing found at all is [GrantStatus.unknown].
GrantStatus readFullDiskAccess({
  ProbeFileSystem fs = const SystemProbeFileSystem(),
  List<String> paths = kFullDiskAccessProbes,
}) {
  final String? home = fs.home;
  bool sawBlocked = false;
  for (final String raw in paths) {
    String path = raw;
    if (path.startsWith('~')) {
      if (home == null || home.isEmpty) continue;
      path = '$home${raw.substring(1)}';
    }
    if (!fs.exists(path)) continue;
    try {
      fs.probe(path);
      return GrantStatus.granted;
    } on Object {
      sawBlocked = true;
    }
  }
  return sawBlocked ? GrantStatus.denied : GrantStatus.unknown;
}
