import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'captured_room.dart';
import 'support.dart';

/// Drives a [RoomScanView] and delivers the finished room.
class RoomScanController extends ChangeNotifier {
  MethodChannel? _channel;
  final StreamController<CapturedRoom> _rooms =
      StreamController<CapturedRoom>.broadcast();
  final StreamController<String> _errors = StreamController<String>.broadcast();
  bool _scanning = false;

  /// Whether a view is attached.
  bool get isAttached => _channel != null;

  /// Whether a scan is currently running.
  bool get isScanning => _scanning;

  /// Finished rooms, one per completed scan.
  ///
  /// A room arrives after [stop], not immediately — RoomPlan runs a
  /// post-processing pass that squares off the walls and settles the
  /// dimensions, and that takes a moment.
  Stream<CapturedRoom> get rooms => _rooms.stream;

  /// Scanning failures, as reported by RoomPlan.
  Stream<String> get errors => _errors.stream;

  /// Whether this device can scan at all, and why not if it cannot.
  static Future<RoomScanSupport> support() async {
    if (!RoomScanView.isSupportedPlatform) {
      return const RoomScanSupport(
        supported: false,
        reason: RoomScanUnsupportedReason.osTooOld,
      );
    }
    const MethodChannel channel = MethodChannel('dev.shakib/roomplan');
    final Map<Object?, Object?>? reply =
        await channel.invokeMethod<Map<Object?, Object?>>('support');
    return RoomScanSupport.fromMap(reply ?? const <Object?, Object?>{});
  }

  /// Wires a view to this controller. Called by [RoomScanView], not by you.
  void attach(MethodChannel channel) {
    _channel = channel;
    channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'event') return null;
      final Object? args = call.arguments;
      if (args is! Map) return null;
      switch (args['type']) {
        case 'room':
          _scanning = false;
          final String? json = args['json'] as String?;
          if (json != null) {
            _rooms.add(
              CapturedRoom.fromJson(json, usdzPath: args['usdz'] as String?),
            );
          }
          notifyListeners();
        case 'error':
          _scanning = false;
          _errors.add(args['message'] as String? ?? 'Scan failed.');
          notifyListeners();
      }
      return null;
    });
    notifyListeners();
  }

  /// Unwires a view. Called by [RoomScanView], not by you.
  void detach() => _channel = null;

  MethodChannel _require() {
    final MethodChannel? c = _channel;
    if (c == null) {
      throw StateError(
        'This RoomScanController is not attached to a view yet. Build the '
        'RoomScanView before calling this, or check isAttached.',
      );
    }
    return c;
  }

  /// Begins scanning.
  Future<void> start() async {
    await _require().invokeMethod<void>('start');
    _scanning = true;
    notifyListeners();
  }

  /// Ends scanning and asks RoomPlan to process what it saw.
  ///
  /// The room arrives on [rooms] once processing finishes.
  Future<void> stop() => _require().invokeMethod<void>('stop');

  @override
  void dispose() {
    _rooms.close();
    _errors.close();
    super.dispose();
  }
}

/// Apple's room-scanning camera view, hosted in Flutter.
///
/// RoomPlan ships `RoomCaptureView`, which draws the live coaching overlay and
/// the wireframe as walls are discovered. Reimplementing that in Flutter would
/// mean redrawing an interface Apple already tuned, so this hosts theirs and
/// hands the result back as data.
///
/// **This needs a LiDAR device.** Most iPhones and iPads do not have one — it
/// is the Pro models and recent iPad Pros. Ask [RoomScanController.support]
/// before you show this, because on anything else it renders [fallback].
class RoomScanView extends StatefulWidget {
  /// Creates a scanning view.
  const RoomScanView({super.key, required this.controller, this.fallback});

  /// Drives the scan and receives the room.
  final RoomScanController controller;

  /// Shown where scanning is impossible — no LiDAR, an old iOS, or a platform
  /// that is not iOS at all.
  final Widget? fallback;

  /// Whether this platform could host the view at all. Says nothing about
  /// LiDAR; use [RoomScanController.support] for that.
  /// Whether this platform could host a scan at all.
  ///
  /// Uses [defaultTargetPlatform] rather than `Platform.isIOS`: importing
  /// `dart:io` here made the whole package impossible to compile for web,
  /// which the `kIsWeb` guards were written to allow. It also lets a widget
  /// test drive the fallback path with `debugDefaultTargetPlatformOverride`.
  static bool get isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<RoomScanView> createState() => _RoomScanViewState();
}

class _RoomScanViewState extends State<RoomScanView> {
  static const String _viewType = 'dev.shakib/roomplan/scan';

  /// Null until the device has been asked. RoomPlan needs LiDAR, and the
  /// platform check alone cannot see that — an iPhone without it used to get
  /// a black UiKitView where the dartdoc promised [RoomScanView.fallback].
  bool? _supported;

  @override
  void initState() {
    super.initState();
    if (!RoomScanView.isSupportedPlatform) {
      _supported = false;
      return;
    }
    unawaited(
      RoomScanController.support().then(
        (RoomScanSupport s) {
          if (mounted) setState(() => _supported = s.supported);
        },
        onError: (_) {
          if (mounted) setState(() => _supported = false);
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RoomScanView.isSupportedPlatform || _supported == false) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    // Still asking. Showing the fallback beats flashing a black rectangle for
    // a frame and then replacing it.
    if (_supported == null) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    return UiKitView(
      viewType: _viewType,
      creationParams: const <String, Object?>{},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (int id) =>
          widget.controller.attach(MethodChannel('$_viewType/$id')),
    );
  }
}
