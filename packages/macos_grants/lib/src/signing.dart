/// How macOS identifies this copy of the app, and what that means for a
/// privacy grant.
library;

/// What the app's signature says about who it is.
enum SigningIdentity {
  /// Signed with a Developer ID certificate: the identity is the team, so a
  /// grant survives an update.
  developerId,

  /// Signed by the App Store, or with a Mac App Store distribution
  /// certificate. Same story as [developerId] for TCC purposes.
  appStore,

  /// Signed ad-hoc (`codesign -s -`). The requirement is the hash of the code
  /// itself, so every build is a different app as far as TCC is concerned.
  adHoc,

  /// No signature at all.
  unsigned,

  /// The question could not be answered — an old macOS, a bundle that could
  /// not be opened, or a platform that is not macOS.
  unknown,
}

/// The result of asking macOS what it makes of this bundle.
///
/// The field that matters most is [valid]. macOS reads an app's identity from
/// its signature *before* it matches a TCC grant to it, so a bundle whose
/// nested code no longer matches its outer seal has no identity to match, and
/// no amount of switching Full Disk Access on will help it.
class SigningStatus {
  /// Everything the platform reported.
  const SigningStatus({
    required this.valid,
    required this.identity,
    this.teamId,
    this.error,
  });

  /// Everything unknown, for platforms and failures where saying "broken"
  /// would be a lie. A check that did not run must never accuse a working app.
  const SigningStatus.unknown({this.error})
      : valid = true,
        identity = SigningIdentity.unknown,
        teamId = null;

  /// Whether the bundle still validates, nested code included.
  ///
  /// False means the copy on disk has been modified since it was sealed —
  /// classically an interrupted or crashed build that rewrote a framework
  /// after the app was signed. Such a copy cannot hold a privacy grant.
  final bool valid;

  /// Who macOS thinks signed it.
  final SigningIdentity identity;

  /// The Developer ID team, when there is one.
  final String? teamId;

  /// Why the check could not run, when it could not.
  final String? error;

  /// Whether a grant given to this copy will still apply after an update.
  ///
  /// Ad-hoc signing makes the code's own hash its identity, so tomorrow's
  /// build is a different app to TCC and the user has to grant access again.
  /// That is not a bug you can fix in a release script; it is the cost of not
  /// having a Developer ID, and an app that knows it can say so.
  bool get survivesUpdate =>
      identity == SigningIdentity.developerId ||
      identity == SigningIdentity.appStore;

  /// Whether this copy can hold a privacy grant at all.
  bool get canHoldGrant => valid;

  @override
  String toString() => 'SigningStatus(valid: $valid, identity: ${identity.name}'
      '${teamId == null ? '' : ', teamId: $teamId'}'
      '${error == null ? '' : ', error: $error'})';
}
