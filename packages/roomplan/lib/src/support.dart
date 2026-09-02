/// Why a device can or cannot scan a room.
enum RoomScanUnsupportedReason {
  /// Scanning is possible.
  supported,

  /// The device has no LiDAR sensor. Most iPhones and iPads do not.
  noLidar,

  /// The system predates RoomPlan, or the app was built without the SDK.
  osTooOld,
}

/// Whether this device can scan, and if not, why not.
///
/// Told apart deliberately. "Your phone has no LiDAR" and "your iOS is too
/// old" call for very different things to be said to a user, and collapsing
/// them into one boolean forces every caller to guess.
class RoomScanSupport {
  /// Creates a support report.
  const RoomScanSupport({required this.supported, required this.reason});

  /// Builds a report from the platform's reply.
  factory RoomScanSupport.fromMap(Map<Object?, Object?> map) => RoomScanSupport(
        supported: map['supported'] as bool? ?? false,
        reason: switch (map['reason'] as String?) {
          'supported' => RoomScanUnsupportedReason.supported,
          'noLidar' => RoomScanUnsupportedReason.noLidar,
          _ => RoomScanUnsupportedReason.osTooOld,
        },
      );

  /// Whether a scan can be started at all.
  final bool supported;

  /// Why, when it cannot.
  final RoomScanUnsupportedReason reason;

  @override
  String toString() => 'RoomScanSupport($supported, ${reason.name})';
}
