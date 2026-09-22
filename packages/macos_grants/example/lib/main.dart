// A diagnostic panel: what this copy of the app is, what it is allowed to do,
// and the one sentence worth showing a user when a grant will not apply.
import 'package:flutter/material.dart';
import 'package:macos_grants/macos_grants.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'macos_grants',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3DDC97)),
          useMaterial3: true,
        ),
        home: const Diagnostics(),
      );
}

class Diagnostics extends StatefulWidget {
  const Diagnostics({super.key});

  @override
  State<Diagnostics> createState() => _DiagnosticsState();
}

class _DiagnosticsState extends State<Diagnostics> {
  SigningStatus? _signing;
  GrantStatus? _fda;
  GrantStatus? _accessibility;
  GrantStatus? _screen;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final SigningStatus signing = await MacGrants.signing();
    final GrantStatus fda = await MacGrants.fullDiskAccess();
    final GrantStatus ax = await MacGrants.accessibility();
    final GrantStatus screen = await MacGrants.screenRecording();
    // Printed so `flutter run` shows the answers without a screenshot.
    debugPrint('signing: $signing');
    debugPrint('fullDiskAccess: ${fda.name} — ${fda.explain(signing)}');
    debugPrint('accessibility: ${ax.name} · screenRecording: ${screen.name}');
    if (!mounted) return;
    setState(() {
      _signing = signing;
      _fda = fda;
      _accessibility = ax;
      _screen = screen;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SigningStatus? signing = _signing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('macos_grants'),
        actions: <Widget>[
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Check again',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          if (!MacGrants.isMacOS)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Not macOS'),
                subtitle: Text(
                  'Every check answers "unknown" here rather than throwing, so '
                  'a cross-platform app can call them unguarded.',
                ),
              ),
            ),
          if (signing != null) _SigningCard(signing: signing),
          const SizedBox(height: 8),
          _GrantTile(
            label: 'Full Disk Access',
            status: _fda,
            signing: signing,
            pane: PrivacyPane.fullDiskAccess,
          ),
          _GrantTile(
            label: 'Accessibility',
            status: _accessibility,
            signing: signing,
            pane: PrivacyPane.accessibility,
          ),
          _GrantTile(
            label: 'Screen Recording',
            status: _screen,
            signing: signing,
            pane: PrivacyPane.screenRecording,
          ),
        ],
      ),
    );
  }
}

class _SigningCard extends StatelessWidget {
  const _SigningCard({required this.signing});

  final SigningStatus signing;

  @override
  Widget build(BuildContext context) {
    final bool broken = !signing.valid;
    return Card(
      color: broken ? Theme.of(context).colorScheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('This copy of the app',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Row('Signature', signing.valid ? 'valid' : 'does not validate'),
            _Row('Signed as', signing.identity.name),
            if (signing.teamId != null) _Row('Team', signing.teamId!),
            _Row(
              'Grant survives an update',
              signing.survivesUpdate ? 'yes' : 'no — ad-hoc identity',
            ),
            if (signing.error != null) _Row('Note', signing.error!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 190, child: Text(label)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _GrantTile extends StatelessWidget {
  const _GrantTile({
    required this.label,
    required this.status,
    required this.signing,
    required this.pane,
  });

  final String label;
  final GrantStatus? status;
  final SigningStatus? signing;
  final PrivacyPane pane;

  @override
  Widget build(BuildContext context) {
    final GrantStatus? s = status;
    final SigningStatus? sign = signing;
    return Card(
      child: ListTile(
        leading: Icon(switch (s) {
          GrantStatus.granted => Icons.check_circle,
          GrantStatus.denied => Icons.cancel,
          _ => Icons.help_outline,
        }),
        title: Text('$label — ${s?.name ?? 'checking'}'),
        subtitle: s == null || sign == null ? null : Text(s.explain(sign)),
        trailing: TextButton(
          onPressed: () => MacGrants.openSettings(pane),
          child: const Text('Open Settings'),
        ),
      ),
    );
  }
}
