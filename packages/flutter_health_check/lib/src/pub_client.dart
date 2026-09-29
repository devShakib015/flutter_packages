import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What pub.dev says about a package's latest version.
class PubInfo {
  /// Information about [name].
  PubInfo({
    required this.name,
    this.latest,
    this.published,
    this.discontinued = false,
    this.replacedBy,
    this.licenses = const [],
    this.points,
    this.maxPoints,
    this.isPlugin = false,
  });

  /// The package name.
  final String name;

  /// The newest version.
  final String? latest;

  /// When [latest] was published.
  final DateTime? published;

  /// Marked discontinued by its publisher.
  final bool discontinued;

  /// The package the publisher names as the replacement, if any.
  final String? replacedBy;

  /// Licences from the score's tags: `mit`, `gpl-3.0`, …
  final List<String> licenses;

  /// pub points granted.
  final int? points;

  /// pub points available.
  final int? maxPoints;

  /// Has platform code (`flutter: plugin:` in its pubspec): the kind of
  /// package that breaks when Android, iOS or Flutter move.
  final bool isPlugin;
}

/// One advisory from the OSV database.
class Vulnerability {
  /// Advisory [id] with its [summary] and [severity].
  Vulnerability(this.id, this.summary, this.severity);

  /// The advisory id, such as GHSA-xxxx-xxxx-xxxx.
  final String id;

  /// One line from the advisory.
  final String summary;

  /// "CRITICAL", "HIGH", "MODERATE", "LOW" when the advisory says; null otherwise.
  final String? severity;
}

/// pub.dev and OSV, read-only, a few requests at a time.
class PubClient {
  /// A client that uses [client] when given (tests pass a mock) and keeps at
  /// most [concurrency] pub.dev requests in flight.
  PubClient({http.Client? client, this.concurrency = 6})
    : _http = client ?? http.Client();

  final http.Client _http;

  /// Requests in flight at most.
  final int concurrency;

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final r = await _http
          .get(Uri.parse(url), headers: {'accept': 'application/json'})
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on Exception {
      return null;
    }
  }

  /// The latest version, maintenance status, licences and points of [name],
  /// or null when pub.dev does not know it.
  Future<PubInfo?> info(String name) async {
    final pkg = await _getJson('https://pub.dev/api/packages/$name');
    if (pkg == null) return null;
    final latest = pkg['latest'] as Map<String, dynamic>?;
    final options = await _getJson(
      'https://pub.dev/api/packages/$name/options',
    );
    final score = await _getJson('https://pub.dev/api/packages/$name/score');
    final tags = ((score?['tags'] as List?) ?? const []).map(
      (t) => t.toString(),
    );
    return PubInfo(
      name: name,
      latest: latest?['version']?.toString(),
      published: DateTime.tryParse(latest?['published']?.toString() ?? ''),
      discontinued: options?['isDiscontinued'] == true,
      replacedBy: options?['replacedBy']?.toString(),
      licenses: tags
          .where((t) => t.startsWith('license:'))
          .map((t) => t.substring(8))
          .toList(),
      points: (score?['grantedPoints'] as num?)?.toInt(),
      maxPoints: (score?['maxPoints'] as num?)?.toInt(),
      isPlugin:
          ((latest?['pubspec'] as Map?)?['flutter'] as Map?)?['plugin'] != null,
    );
  }

  /// [names] fetched with at most [concurrency] in flight.
  Future<Map<String, PubInfo>> infos(Iterable<String> names) async {
    final out = <String, PubInfo>{};
    final queue = names.toList();
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final n = queue.removeLast();
        final i = await info(n);
        if (i != null) out[n] = i;
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return out;
  }

  /// Known advisories for the locked versions, from the OSV database (which
  /// covers the Pub ecosystem, including GitHub's advisories).
  Future<Map<String, List<Vulnerability>>> vulnerabilities(
    Map<String, String> versions,
  ) async {
    if (versions.isEmpty) return {};
    final names = versions.keys.toList();
    http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse('https://api.osv.dev/v1/querybatch'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'queries': [
                for (final n in names)
                  {
                    'package': {'name': n, 'ecosystem': 'Pub'},
                    'version': versions[n],
                  },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on Exception {
      throw StateError('OSV unreachable');
    }
    if (r.statusCode != 200) throw StateError('OSV answered ${r.statusCode}');
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final results = (body['results'] as List?) ?? const [];
    final out = <String, List<Vulnerability>>{};
    for (var i = 0; i < results.length && i < names.length; i++) {
      final result = results[i] as Map<String, dynamic>;
      final ids = ((result['vulns'] as List?) ?? const []).map(
        (v) => (v as Map<String, dynamic>)['id'].toString(),
      );
      for (final id in ids) {
        final v = await _getJson('https://api.osv.dev/v1/vulns/$id');
        final sev = (v?['database_specific'] as Map?)?['severity']?.toString();
        out
            .putIfAbsent(names[i], () => [])
            .add(
              Vulnerability(
                id,
                v?['summary']?.toString() ??
                    (v?['details']?.toString() ?? '').split('\n').first,
                sev,
              ),
            );
      }
    }
    return out;
  }

  /// Closes the HTTP client.
  void close() => _http.close();
}
