/// What a check reports: one problem, how bad it is, where, and what to do.
library;

/// How much a finding matters, and what it costs its area's score.
enum Severity {
  /// Blocks a store release, or exposes users or data now.
  critical('Critical', 40, cap: 39),

  /// Fix before the next release.
  high('High', 20, cap: 74),

  /// Costs time or users; fix soon.
  medium('Medium', 8),

  /// Worth doing while nearby.
  low('Low', 3),

  /// Context only; costs nothing.
  info('Info', 0);

  const Severity(this.label, this.weight, {this.cap = 100});

  /// The name shown in reports.
  final String label;

  /// Points taken off the area's score of 100.
  final int weight;

  /// The most an area (and the whole report) can score while a finding of
  /// this severity is open: one critical fails its area whatever else is fine.
  final int cap;
}

/// The report's sections, each scored out of 100.
enum Area {
  /// pub.dev packages: updates, advisories, maintenance, licences.
  dependencies('Dependencies'),

  /// Google Play's requirements and the Android build.
  android('Android & Google Play'),

  /// The App Store's requirements and the iOS build.
  ios('iOS & App Store'),

  /// Secrets, signing keys, Firebase rules and transport security.
  security('Security & secrets'),

  /// Analyzer results and lint setup.
  code('Code health'),

  /// Tests and CI.
  testing('Tests & CI'),

  /// What the app bundles, and how big it is.
  assets('Assets & size');

  const Area(this.label);

  /// The section title shown in reports.
  final String label;
}

/// One problem: how bad it is, where, and what to do about it.
class Finding {
  /// A finding with a stable [id].
  Finding({
    required this.id,
    required this.area,
    required this.severity,
    required this.title,
    required this.detail,
    this.fix,
    this.locations = const [],
  });

  /// Stable, e.g. `android.target-sdk` — tests pin these, and a client can
  /// waive one they have accepted without the rest of the report moving.
  final String id;

  /// The report section it belongs to.
  final Area area;

  /// How much it matters.
  final Severity severity;

  /// One line. May contain `code` spans in backticks.
  final String title;

  /// Why it matters, in a sentence or two.
  final String detail;

  /// What to do about it.
  final String? fix;

  /// `path:line` references, relative to the project root.
  final List<String> locations;
}

/// A row in the dependency table: what is locked, what is current.
class DependencyRow {
  /// A row for [name] as locked, with what pub.dev knows about it.
  DependencyRow({
    required this.name,
    required this.kind,
    required this.locked,
    this.latest,
    this.published,
    this.points,
    this.maxPoints,
    this.discontinued = false,
    this.vulnerabilities = const [],
  });

  /// The package name.
  final String name;

  /// "direct main", "direct dev" or "transitive".
  final String kind;

  /// The version in pubspec.lock.
  final String locked;

  /// The newest version on pub.dev, when it could be read.
  final String? latest;

  /// When [latest] was published.
  final DateTime? published;

  /// pub points granted.
  final int? points;

  /// pub points available.
  final int? maxPoints;

  /// Marked discontinued on pub.dev.
  final bool discontinued;

  /// Advisory ids (OSV) that affect the locked version.
  final List<String> vulnerabilities;

  /// Breaking releases between what is locked and what is current. Under 1.0 a
  /// minor bump is the breaking one; crossing into 1.0 counts every major on
  /// the way (0.9 → 3.1 is three: 1.0, 2.0, 3.0).
  int? get majorsBehind {
    final a = _parts(locked), b = latest == null ? null : _parts(latest!);
    if (a == null || b == null) return null;
    if (a.$1 == 0 && b.$1 == 0) return b.$2 - a.$2;
    if (a.$1 == 0) return b.$1;
    return b.$1 - a.$1;
  }

  static (int, int)? _parts(String v) {
    final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(v);
    return m == null ? null : (int.parse(m[1]!), int.parse(m[2]!));
  }
}

/// Facts about the project that belong in the report whether or not they are
/// problems: versions, toolchain, platforms.
class ProjectFacts {
  /// The facts, in the order they were added.
  final Map<String, String> values = {};

  /// Sets the fact [key].
  void operator []=(String key, String value) => values[key] = value;
}

/// The result of a run: findings, scores, and what could not be checked.
class Report {
  /// A report for [projectName]; [findings] leave out the [waived] ones.
  Report({
    required this.projectName,
    required this.generated,
    required this.findings,
    required this.dependencies,
    required this.facts,
    required this.notes,
    this.waived = const [],
    this.skipped = const {},
    this.auditedWith,
  });

  /// The pubspec name.
  final String projectName;

  /// When the run happened.
  final DateTime generated;

  /// Open findings, in the order the checks produced them; see [prioritised].
  final List<Finding> findings;

  /// Findings the project owner has accepted, with their reason. Listed in
  /// the report, left out of the scores.
  final List<(Finding, String)> waived;

  /// Areas that could not be checked (no ios/ folder, say): shown as such
  /// and left out of the overall score rather than scored 100.
  final Set<Area> skipped;

  /// The Flutter version the checks ran against.
  final String? auditedWith;

  /// The dependency table: direct packages, and any transitive one with an
  /// advisory.
  final List<DependencyRow> dependencies;

  /// Facts about the project that are not problems.
  final ProjectFacts facts;

  /// Checks that could not run, and why — a report must say what it skipped.
  final List<String> notes;

  /// Every area, in report order.
  List<Area> get areas => Area.values;

  /// The areas that were checked, and so count toward [overall].
  List<Area> get scoredAreas => [
    for (final a in areas)
      if (!skipped.contains(a)) a,
  ];

  /// 100 minus the weights of [area]'s findings, capped by the worst one.
  int scoreFor(Area area) {
    final open = findings.where((f) => f.area == area);
    final lost = open.fold<int>(0, (sum, f) => sum + f.severity.weight);
    final cap = open.fold<int>(
      100,
      (c, f) => f.severity.cap < c ? f.severity.cap : c,
    );
    return (100 - lost).clamp(0, cap);
  }

  /// The average of the checked areas, capped like an area: an average hides
  /// one open database behind six clean areas, and the headline must not.
  int get overall {
    final scored = scoredAreas.map(scoreFor).toList();
    if (scored.isEmpty) return 0;
    final average = (scored.reduce((a, b) => a + b) / scored.length).round();
    final worst = findings.fold<int>(
      100,
      (c, f) => f.severity.cap < c ? f.severity.cap : c,
    );
    // Across the whole app the critical cap is a D, not an F: one failed
    // area is not a failed app.
    return average.clamp(0, worst == Severity.critical.cap ? 59 : worst);
  }

  /// A to F for a score; the boundaries are 90, 75, 60 and 40.
  static String grade(int score) => score >= 90
      ? 'A'
      : score >= 75
      ? 'B'
      : score >= 60
      ? 'C'
      : score >= 40
      ? 'D'
      : 'F';

  /// The findings, most severe first, then in area order.
  List<Finding> get prioritised => [...findings]
    ..sort(
      (a, b) => a.severity.index != b.severity.index
          ? a.severity.index.compareTo(b.severity.index)
          : a.area.index.compareTo(b.area.index),
    );
}
