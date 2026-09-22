// The web is off macOS too, and the one place dart:io's Platform throws
// rather than answering false. Because this file is browser-only, CI runs
// every test in the package in Chrome, the off-macOS group included. Each call
// gets its own test here, since a failing browser test reports only that it
// failed.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:macos_grants/macos_grants.dart';

void main() {
  test('the web is not macOS', () {
    expect(MacGrants.isMacOS, isFalse);
  });

  test('signing is unknown, and does not call the copy broken', () async {
    final SigningStatus s = await MacGrants.signing();
    expect(s.identity, SigningIdentity.unknown);
    expect(s.valid, isTrue);
  });

  test('Full Disk Access is unknown', () async {
    expect(await MacGrants.fullDiskAccess(), GrantStatus.unknown);
  });

  test('Accessibility is unknown', () async {
    expect(await MacGrants.accessibility(), GrantStatus.unknown);
  });

  test('Screen Recording is unknown', () async {
    expect(await MacGrants.screenRecording(), GrantStatus.unknown);
  });

  test('no Settings pane opens', () async {
    expect(await MacGrants.openSettings(PrivacyPane.fullDiskAccess), isFalse);
  });
}
