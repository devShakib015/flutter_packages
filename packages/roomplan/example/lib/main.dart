import 'dart:async';

import 'package:flutter/material.dart';
import 'package:roomplan/roomplan.dart';

void main() => runApp(const Demo());

class Demo extends StatelessWidget {
  const Demo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'roomplan',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF4C6FFF),
          useMaterial3: true,
        ),
        home: const ScanPage(),
      );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final RoomScanController _controller = RoomScanController();
  final List<StreamSubscription<Object?>> _subs =
      <StreamSubscription<Object?>>[];
  RoomScanSupport? _support;
  CapturedRoom? _room;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _controller.rooms.listen((CapturedRoom r) {
        if (mounted) setState(() => _room = r);
      }),
    );
    _subs.add(
      _controller.errors.listen((String e) {
        if (mounted) setState(() => _error = e);
      }),
    );
    unawaited(_check());
  }

  @override
  void dispose() {
    for (final StreamSubscription<Object?> s in _subs) {
      s.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final RoomScanSupport s = await RoomScanController.support();
    if (mounted) setState(() => _support = s);
  }

  @override
  Widget build(BuildContext context) {
    final RoomScanSupport? s = _support;
    return Scaffold(
      appBar: AppBar(title: const Text('roomplan')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              s == null
                  ? 'checking…'
                  : s.supported
                      ? 'This device can scan.'
                      : switch (s.reason) {
                          RoomScanUnsupportedReason.noLidar =>
                            'This device has no LiDAR sensor, so it cannot scan. '
                                'RoomPlan needs a Pro iPhone or iPad Pro.',
                          _ => 'This iOS version predates RoomPlan.',
                        },
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: RoomScanView(
              controller: _controller,
              fallback: const Center(
                child: Text('Scanning needs an iOS device.'),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_room != null) _Summary(room: _room!),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                FilledButton(
                  onPressed: s?.supported == true && !_controller.isScanning
                      ? () => _controller.start()
                      : null,
                  child: const Text('Start'),
                ),
                OutlinedButton(
                  onPressed:
                      s?.supported == true ? () => _controller.stop() : null,
                  child: const Text('Stop and process'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.room});

  final CapturedRoom room;

  @override
  Widget build(BuildContext context) {
    final double area = room.floors.fold<double>(
      0,
      (double sum, RoomSurface f) => sum + f.dimensions.x * f.dimensions.z,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${room.walls.length} walls · ${room.doors.length} doors · '
            '${room.windows.length} windows · ${room.objects.length} objects',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (area > 0)
            Text(
              'floor area ~${area.toStringAsFixed(1)} m²',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          if (room.usdzPath != null)
            Text(
              'USDZ: ${room.usdzPath}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}
