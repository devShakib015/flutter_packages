import 'package:flutter/material.dart';
import 'package:vitals/vitals.dart';

void main() => runApp(const VitalsDemo());

/// Demonstrates availability, permissions, and bucketed statistics.
class VitalsDemo extends StatelessWidget {
  /// Creates the demo.
  const VitalsDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'vitals',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF11A97C)),
      home: const DemoPage(),
    );
  }
}

/// The demo's single screen.
class DemoPage extends StatefulWidget {
  /// Creates the page.
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  /// Swap for `FakeVitals()` to run this without a device.
  final Vitals _vitals = Vitals.instance;

  bool? _available;
  String _status = '';
  List<VitalStatistic> _steps = const <VitalStatistic>[];

  static const PermissionRequest _wanted = PermissionRequest(
    read: <VitalType<VitalSample>>{
      VitalType.steps,
      VitalType.heartRate,
      VitalType.bodyMass,
    },
    write: <VitalType<VitalSample>>{VitalType.water},
  );

  @override
  void initState() {
    super.initState();
    _vitals.isAvailable().then(
      (bool ok) => mounted ? setState(() => _available = ok) : null,
    );
  }

  Future<void> _request() async {
    final bool completed = await _vitals.requestPermissions(_wanted);
    if (!mounted) return;
    setState(
      () => _status = completed
          ? 'Sheet completed. On iOS this does not tell you what was granted.'
          : 'The sheet was dismissed or failed.',
    );
  }

  Future<void> _loadSteps() async {
    final DateTime now = DateTime.now();
    final List<VitalStatistic> stats = await _vitals.statistics(
      VitalType.steps,
      from: now.subtract(const Duration(days: 7)),
      to: now,
      bucket: VitalBucket.daily,
    );
    if (!mounted) return;
    setState(() {
      _steps = stats;
      _status = stats.every((VitalStatistic s) => !s.hasData)
          ? 'No step data. Either permission was refused or there is none — '
                'iOS cannot tell you which.'
          : 'Loaded ${stats.length} days.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('vitals')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Card(
            child: ListTile(
              title: const Text('Health data available'),
              subtitle: Text(switch (_available) {
                null => 'checking…',
                true => 'yes',
                false => 'no — needs HealthKit or Health Connect',
              }),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _request,
            child: const Text('Request permissions'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadSteps,
            child: const Text('Steps, last 7 days'),
          ),
          if (_status.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          for (final VitalStatistic day in _steps)
            ListTile(
              dense: true,
              title: Text(day.start.toIso8601String().split('T').first),
              trailing: Text(
                day.hasData ? day.value!.round().toString() : '—',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  // A recorded zero and no data are different, and the UI
                  // should say so rather than printing 0 for both.
                  color: day.hasData ? null : Theme.of(context).disabledColor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
