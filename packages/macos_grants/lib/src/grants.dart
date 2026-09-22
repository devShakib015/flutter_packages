/// The API: what this copy of the app is, and what it is allowed to do.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import 'probe.dart';
import 'signing.dart';

/// A pane of System Settings ▸ Privacy & Security.
///
/// None of these grants can be requested from code — macOS shows no prompt for
/// them — so the most an app can do is take the user to the right switch.
enum PrivacyPane {
  /// Files and folders the system protects: Mail, Messages, Safari, backups.
  fullDiskAccess('Privacy_AllFiles'),

  /// Control of other apps, and reading the window tree.
  accessibility('Privacy_Accessibility'),

  /// Capturing the screen or its contents.
  screenRecording('Privacy_ScreenCapture'),

  /// Reading key presses outside the app.
  inputMonitoring('Privacy_ListenEvent'),

  /// Driving other apps through AppleScript.
  automation('Privacy_Automation'),

  /// Running developer tooling without prompting each time.
  developerTools('Privacy_DevTools');

  const PrivacyPane(this.anchor);

  /// The anchor System Settings knows this pane by.
  final String anchor;

  /// The URL that opens it.
  String get url =>
      'x-apple.systempreferences:com.apple.preference.security?$anchor';
}

/// Privacy grants on macOS, reported honestly.
///
/// Two questions, and the second is the one nobody asks: does this app have
/// the grant, and *can* it hold one at all? macOS matches a TCC grant against
/// the app's code signature, so a copy whose signature no longer validates can
/// be switched on all day and stay blocked. An app that checks can say
/// "reinstall this copy" instead of "relaunch", which is a loop with no exit.
///
/// Every method answers [GrantStatus.unknown] or a permissive default rather
/// than guessing. Nothing here prompts, because macOS has no prompt to show.
abstract final class MacGrants {
  static const MethodChannel _channel =
      MethodChannel('dev.shakib/macos_grants');

  /// Whether this is a Mac at all. Everything else returns an unknown/neutral
  /// answer off macOS rather than throwing, so a cross-platform app can call
  /// these without guarding every line.
  ///
  /// The web is asked about first because dart:io's `Platform` throws there
  /// rather than answering false.
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// What macOS makes of this bundle's signature.
  ///
  /// Hashing a bundle is not instant — the check runs off the main thread on
  /// the native side — so call it when something is wrong, not every frame.
  static Future<SigningStatus> signing() async {
    if (!isMacOS) {
      return const SigningStatus.unknown(error: 'not macOS');
    }
    try {
      final Map<Object?, Object?>? raw =
          await _channel.invokeMapMethod<Object?, Object?>('signing');
      if (raw == null) return const SigningStatus.unknown(error: 'no answer');
      return SigningStatus(
        valid: raw['valid'] as bool? ?? true,
        identity: _identity(raw['identity'] as String?),
        teamId: raw['teamId'] as String?,
        error: raw['error'] as String?,
      );
    } on PlatformException catch (e) {
      return SigningStatus.unknown(error: e.message);
    } on MissingPluginException {
      return const SigningStatus.unknown(error: 'plugin not registered');
    }
  }

  /// Whether the app can read the files Full Disk Access protects.
  ///
  /// There is no API for this grant, so this opens something it protects and
  /// reports what happened. A sandboxed app cannot reach the probes at all and
  /// gets [GrantStatus.unknown].
  static Future<GrantStatus> fullDiskAccess() async {
    if (!isMacOS) return GrantStatus.unknown;
    return readFullDiskAccess();
  }

  /// Whether the app is trusted for Accessibility (`AXIsProcessTrusted`).
  static Future<GrantStatus> accessibility() => _ask('accessibility');

  /// Whether screen recording is allowed (`CGPreflightScreenCaptureAccess`).
  ///
  /// Screen Recording became a grant in macOS 10.15. On 10.14 every app could
  /// capture the screen, so there this answers [GrantStatus.granted].
  static Future<GrantStatus> screenRecording() => _ask('screenRecording');

  /// Open the Settings pane for [pane]. Returns false if it could not be
  /// opened, which on a Mac usually means the anchor has been renamed.
  static Future<bool> openSettings(PrivacyPane pane) async {
    if (!isMacOS) return false;
    try {
      final ProcessResult r = await Process.run('open', <String>[pane.url]);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<GrantStatus> _ask(String method) async {
    if (!isMacOS) return GrantStatus.unknown;
    try {
      final bool? granted = await _channel.invokeMethod<bool>(method);
      if (granted == null) return GrantStatus.unknown;
      return granted ? GrantStatus.granted : GrantStatus.denied;
    } on PlatformException {
      return GrantStatus.unknown;
    } on MissingPluginException {
      return GrantStatus.unknown;
    }
  }

  static SigningIdentity _identity(String? name) => switch (name) {
        'developerId' => SigningIdentity.developerId,
        'appStore' => SigningIdentity.appStore,
        'adHoc' => SigningIdentity.adHoc,
        'unsigned' => SigningIdentity.unsigned,
        _ => SigningIdentity.unknown,
      };
}

/// The two answers together, for the case this package exists for.
extension GrantDiagnosis on GrantStatus {
  /// Why a grant is not working, given what the signature says.
  ///
  /// [GrantStatus.denied] with a bundle that does not validate is the case
  /// where "relaunch and try again" never ends: the switch cannot apply to
  /// this copy. Say *reinstall*.
  String explain(SigningStatus signing) {
    // A broken signature explains a refusal, but it does not contradict what
    // the app can plainly do. Telling somebody to reinstall while the thing
    // works is the same unhelpful noise as telling them to relaunch when it
    // cannot: say what is true, then add the caveat.
    if (this == GrantStatus.granted) {
      return signing.valid
          ? 'Access is granted.'
          : 'Access is granted, but this copy of the app has been modified '
              'since it was signed. Reinstall it before relying on that.';
    }
    if (!signing.valid) {
      return 'This copy of the app has been modified since it was signed, so '
          'macOS cannot match a privacy grant to it. Reinstall it, then grant '
          'access again.';
    }
    return switch (this) {
      GrantStatus.denied => signing.survivesUpdate
          ? 'Access is turned off. Grant it in System Settings ▸ Privacy & '
              'Security.'
          : 'Access is turned off. Note that this build is signed ad-hoc, so '
              'macOS treats every update as a new app and the grant has to be '
              'given again after each one.',
      _ => 'Access could not be determined.',
    };
  }
}
