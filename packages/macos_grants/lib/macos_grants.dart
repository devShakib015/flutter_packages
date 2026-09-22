/// macOS privacy grants, reported honestly — including whether this copy of
/// the app can hold one at all.
library;

export 'src/grants.dart' show GrantDiagnosis, MacGrants, PrivacyPane;
export 'src/probe.dart'
    show GrantStatus, ProbeFileSystem, SystemProbeFileSystem, kFullDiskAccessProbes, readFullDiskAccess;
export 'src/signing.dart' show SigningIdentity, SigningStatus;
