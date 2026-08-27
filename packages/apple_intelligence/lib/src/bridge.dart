import 'package:flutter/services.dart';

/// The channels this package talks over.
///
/// Kept in one place so tests can swap the handlers without reaching into
/// every call site.
class Bridge {
  const Bridge._();

  /// Request/response channel.
  static const MethodChannel method = MethodChannel(
    'dev.shakib/apple_intelligence',
  );

  /// Streamed generation results.
  static const EventChannel events = EventChannel(
    'dev.shakib/apple_intelligence/events',
  );
}
