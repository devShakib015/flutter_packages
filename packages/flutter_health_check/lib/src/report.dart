import 'dart:convert';

import 'facts.dart';
import 'model.dart';

/// What a file-reading tool cannot see. Printed at the end of every report
/// so nobody mistakes a clean score for a clean app.
const beyondThisReport = <(String, String)>[
  (
    'Permissions added by plugins',
    'Plugins merge their own permissions into the Android manifest at build time. Check the '
        'merged manifest of a release build (Android Studio: Merged Manifest tab) against '
        'what the app needs.',
  ),
  (
    '16 KB memory pages',
    'Google Play requires apps targeting Android 15 or later to support 16 KB page sizes. '
        'Native libraries from plugins can fail this; check the release bundle in Android '
        'Studio\'s APK Analyzer.',
  ),
  (
    'Privacy manifests',
    'App Store Connect checks required-reason APIs and third-party SDK privacy manifests '
        'when a build is uploaded, and reports problems by email (ITMS-91053, ITMS-91061).',
  ),
  (
    'Store privacy answers',
    'The Play Data safety form and the App Store privacy labels must match what the app and '
        'every SDK in it collect.',
  ),
  (
    'Account deletion',
    'If users can create an account, the App Store requires a way to delete it inside the '
        'app, and Google Play requires a web link for deletion requests.',
  ),
  (
    'Runtime behaviour',
    'Startup time, jank, memory and battery need a profile build on a real low-end device; '
        'crashes need the production crash reports.',
  ),
  (
    'Design of the code',
    'Whether the architecture will survive the next year of features is a judgement a '
        'person makes by reading it.',
  ),
];

String _date(DateTime d) =>
    '${d.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]} ${d.year}';

String _counts(Iterable<Finding> findings) {
  final parts = [
    for (final s in Severity.values)
      if (s != Severity.info && findings.any((f) => f.severity == s))
        '${findings.where((f) => f.severity == s).length} ${s.label.toLowerCase()}',
  ];
  return parts.isEmpty ? 'no findings' : parts.join(', ');
}

String _dependencyNote(DependencyRow d, DateTime now) => [
  if (d.discontinued) 'discontinued',
  if (d.vulnerabilities.isNotEmpty) d.vulnerabilities.join(', '),
  if ((d.majorsBehind ?? 0) >= 1)
    '${d.majorsBehind} breaking release${d.majorsBehind == 1 ? '' : 's'} behind',
  if (d.published != null && now.difference(d.published!).inDays > 730)
    'no release since ${d.published!.year}',
].join('; ');

/// "direct main" → "app", "direct dev" → "dev only", "transitive" → "another package".
String _kind(String kind) => switch (kind) {
  'direct main' => 'app',
  'direct dev' => 'dev only',
  'transitive' => 'another package',
  _ => kind,
};

/// The report as Markdown, for a README, a pull request or a ticket.
String toMarkdown(Report r) {
  final b = StringBuffer();
  final overall = r.overall;
  b.writeln('# Flutter health check: ${r.projectName}');
  b.writeln();
  b.writeln(
    '${_date(r.generated)}'
    '${r.auditedWith == null ? '' : ' · checked against Flutter ${r.auditedWith}'}'
    ' · fhc',
  );
  b.writeln();
  b.writeln(
    '**Overall: $overall / 100 (${Report.grade(overall)})** · ${_counts(r.findings)}',
  );
  b.writeln();
  b.writeln('| Area | Score | Grade | Findings |');
  b.writeln('|---|---:|:---:|---|');
  for (final a in r.areas) {
    final s = r.scoreFor(a);
    b.writeln(
      r.skipped.contains(a)
          ? '| ${a.label} | – | – | not checked |'
          : '| ${a.label} | $s | ${Report.grade(s)} | ${_counts(r.findings.where((f) => f.area == a))} |',
    );
  }
  b.writeln();

  final first = r.prioritised
      .where((f) => f.severity.index <= Severity.high.index)
      .take(10)
      .toList();
  if (first.isNotEmpty) {
    b.writeln('## Fix first');
    b.writeln();
    for (final (i, f) in first.indexed) {
      b.writeln(
        '${i + 1}. **${f.severity.label}:** ${f.title} (${f.area.label})',
      );
    }
    b.writeln();
  }

  b.writeln('## Findings');
  b.writeln();
  for (final a in r.areas) {
    final list = r.prioritised.where((f) => f.area == a).toList();
    if (list.isEmpty) continue;
    b.writeln(
      '### ${a.label}: ${r.scoreFor(a)} (${Report.grade(r.scoreFor(a))})',
    );
    b.writeln();
    for (final f in list) {
      b.writeln('#### ${f.severity.label}: ${f.title}');
      b.writeln();
      b.writeln(f.detail);
      b.writeln();
      if (f.fix != null) {
        b.writeln('**Fix:** ${f.fix}');
        b.writeln();
      }
      if (f.locations.isNotEmpty) {
        b.writeln(
          f.locations.take(10).map((l) => '`$l`').join(' · ') +
              (f.locations.length > 10
                  ? ' · and ${f.locations.length - 10} more'
                  : ''),
        );
        b.writeln();
      }
      b.writeln('<sub>${f.id}</sub>');
      b.writeln();
    }
  }

  if (r.dependencies.isNotEmpty) {
    b.writeln('## Dependencies');
    b.writeln();
    b.writeln(
      '| Package | Used by | Locked | Latest | Last release | pub points | Notes |',
    );
    b.writeln('|---|---|---|---|---|---:|---|');
    for (final d in r.dependencies) {
      b.writeln(
        '| ${d.name} | ${_kind(d.kind)} | ${d.locked} | ${d.latest ?? ''} | '
        '${d.published == null ? '' : d.published!.toIso8601String().substring(0, 10)} | '
        '${d.points == null ? '' : '${d.points}/${d.maxPoints}'} | ${_dependencyNote(d, r.generated)} |',
      );
    }
    b.writeln();
  }

  b.writeln('## Project facts');
  b.writeln();
  b.writeln('| | |');
  b.writeln('|---|---|');
  for (final e in r.facts.values.entries) {
    b.writeln('| ${e.key} | ${e.value.replaceAll('|', '\\|')} |');
  }
  b.writeln();

  if (r.notes.isNotEmpty) {
    b.writeln('## Not checked');
    b.writeln();
    for (final n in r.notes) {
      b.writeln('- $n');
    }
    b.writeln();
  }
  if (r.waived.isNotEmpty) {
    b.writeln('## Accepted by the project');
    b.writeln();
    for (final (f, reason) in r.waived) {
      b.writeln('- **${f.severity.label}:** ${f.title} (`${f.id}`). $reason');
    }
    b.writeln();
  }
  b.writeln('## Beyond this report');
  b.writeln();
  b.writeln(
    'This report reads the project\'s files. These need a build, a store account or a '
    'person:',
  );
  b.writeln();
  for (final (title, text) in beyondThisReport) {
    b.writeln('- **$title.** $text');
  }
  b.writeln();
  b.writeln(
    'Store rules as of ${_date(r.generated)}: Google Play target API '
    '${StoreRules.playTargetSdk} (${StoreRules.playSource}); App Store builds with '
    '${StoreRules.appStoreSdk} (${StoreRules.appStoreSource}).',
  );
  return b.toString();
}

/// The report as JSON, for CI and other tools.
String toJson(Report r) => const JsonEncoder.withIndent('  ').convert({
  'tool': 'fhc',
  'project': r.projectName,
  'generated': r.generated.toIso8601String(),
  'auditedWith': r.auditedWith,
  'overall': r.overall,
  'grade': Report.grade(r.overall),
  'areas': [
    for (final a in r.areas)
      {
        'area': a.name,
        'label': a.label,
        'score': r.scoreFor(a),
        'grade': Report.grade(r.scoreFor(a)),
      },
  ],
  'findings': [for (final f in r.prioritised) _findingJson(f)],
  'waived': [
    for (final (f, reason) in r.waived) {..._findingJson(f), 'reason': reason},
  ],
  'dependencies': [
    for (final d in r.dependencies)
      {
        'name': d.name,
        'kind': d.kind,
        'locked': d.locked,
        'latest': d.latest,
        'published': d.published?.toIso8601String(),
        'points': d.points,
        'maxPoints': d.maxPoints,
        'discontinued': d.discontinued,
        'vulnerabilities': d.vulnerabilities,
      },
  ],
  'facts': r.facts.values,
  'notes': r.notes,
});

Map<String, Object?> _findingJson(Finding f) => {
  'id': f.id,
  'area': f.area.name,
  'severity': f.severity.name,
  'title': f.title,
  'detail': f.detail,
  'fix': f.fix,
  'locations': f.locations,
};

String _esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);

/// Escapes, then renders `code` spans and bare URLs.
String _inline(String s) => _esc(s)
    .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>')
    .replaceAllMapped(
      RegExp(r'https?://[^\s<]+[^\s<.,;:)]'),
      (m) => '<a href="${m[0]}">${m[0]}</a>',
    );

/// The report as one self-contained HTML page: light and dark, and
/// printable.
String toHtml(Report r) {
  final overall = r.overall;
  final grade = Report.grade(overall);
  final b = StringBuffer();
  const circumference = 2 * 3.14159265 * 52;
  b.write('''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Health check: ${_esc(r.projectName)}</title>
<style>
:root {
  --bg: #f6f7f9; --card: #ffffff; --ink: #14161a; --muted: #5d6470; --line: #e3e6eb;
  --critical: #c62828; --high: #e0591b; --medium: #b7860b; --low: #3b6ea8; --info: #6b7280;
  --a: #1b8a5a; --b: #3f8f3a; --c: #b7860b; --d: #e0591b; --f: #c62828;
  --code: #eef0f3;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f1115; --card: #171a20; --ink: #e8eaee; --muted: #9aa1ad; --line: #2a2f38;
    --critical: #ff6b6b; --high: #ff9254; --medium: #f2c14e; --low: #7fb0ff; --info: #9aa1ad;
    --a: #4cc38a; --b: #7dc46f; --c: #f2c14e; --d: #ff9254; --f: #ff6b6b;
    --code: #232833;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink);
  font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", Inter, Roboto, sans-serif; }
main { max-width: 960px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { font-size: 30px; line-height: 1.2; margin: 4px 0 6px; letter-spacing: -0.01em; }
h2 { font-size: 20px; margin: 40px 0 14px; letter-spacing: -0.01em; }
h3 { font-size: 16px; margin: 0; }
.eyebrow { text-transform: uppercase; letter-spacing: .08em; font-size: 12px; color: var(--muted); font-weight: 600; }
.sub { color: var(--muted); margin: 0; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; }
.hero { display: grid; grid-template-columns: 1fr auto; gap: 24px; align-items: center; padding: 28px; }
.ring { position: relative; width: 132px; height: 132px; }
.ring svg { transform: rotate(-90deg); }
.ring .num { position: absolute; inset: 0; display: grid; place-items: center; text-align: center; }
.ring .num b { font-size: 34px; line-height: 1; display: block; }
.ring .num span { font-size: 12px; color: var(--muted); }
.tally { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 14px; }
.chip { font-size: 12px; font-weight: 600; padding: 3px 9px; border-radius: 999px; border: 1px solid currentColor; }
.sev-critical { color: var(--critical); } .sev-high { color: var(--high); } .sev-medium { color: var(--medium); }
.sev-low { color: var(--low); } .sev-info { color: var(--info); }
.areas { display: grid; grid-template-columns: repeat(auto-fill, minmax(210px, 1fr)); gap: 12px; margin-top: 16px; }
.area { padding: 14px 16px; }
.area .row { display: flex; justify-content: space-between; align-items: baseline; }
.area .label { font-weight: 600; font-size: 14px; }
.area .grade { font-weight: 700; font-size: 18px; }
.bar { height: 6px; background: var(--line); border-radius: 3px; margin: 10px 0 6px; overflow: hidden; }
.bar i { display: block; height: 100%; border-radius: 3px; }
.area .count { font-size: 12px; color: var(--muted); }
.g-A { color: var(--a); } .g-B { color: var(--b); } .g-C { color: var(--c); } .g-D { color: var(--d); } .g-F { color: var(--f); }
.bg-A { background: var(--a); } .bg-B { background: var(--b); } .bg-C { background: var(--c); } .bg-D { background: var(--d); } .bg-F { background: var(--f); }
ol.first { padding: 18px 18px 18px 40px; margin: 0; }
ol.first li { margin: 6px 0; }
.finding { padding: 18px 20px; margin: 10px 0; border-left: 4px solid currentColor; break-inside: avoid; }
.finding h3 { color: var(--ink); }
.finding p { margin: 8px 0 0; color: var(--ink); }
.finding .fix { color: var(--ink); }
.finding .fix b { font-weight: 600; }
.finding code, .finding a { color: var(--ink); }
.badge { display: inline-block; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: .06em; margin-bottom: 4px; }
.locs { margin-top: 10px; display: flex; flex-wrap: wrap; gap: 6px; }
code { font: 12.5px/1.4 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; background: var(--code); padding: 1px 6px; border-radius: 5px; overflow-wrap: anywhere; }
.id { color: var(--muted); font-size: 11px; margin-top: 8px; }
.area-head { display: flex; justify-content: space-between; align-items: baseline; margin: 34px 0 6px; }
.area-head h2 { margin: 0; }
table { width: 100%; min-width: 640px; border-collapse: collapse; font-size: 13px; }
td code { white-space: nowrap; overflow-wrap: normal; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
th { color: var(--muted); font-weight: 600; font-size: 12px; }
.tablewrap { overflow-x: auto; }
dl.facts { display: grid; grid-template-columns: minmax(160px, 34%) 1fr; margin: 0; padding: 6px 18px; }
dl.facts dt, dl.facts dd { padding: 8px 0; border-bottom: 1px solid var(--line); margin: 0; }
dl.facts dt { color: var(--muted); padding-right: 12px; }
ul.plain { padding: 14px 18px 14px 36px; margin: 0; }
ul.plain li { margin: 6px 0; }
a { color: inherit; }
footer { color: var(--muted); font-size: 12px; margin-top: 40px; }
@media (max-width: 600px) {
  .hero { grid-template-columns: 1fr; }
  dl.facts { grid-template-columns: 1fr; }
  dl.facts dt { border-bottom: 0; padding-bottom: 0; }
}
@media print {
  body { background: #fff; }
  .card { border-color: #ddd; }
  h2 { break-after: avoid; }
}
</style>
</head>
<body>
<main>
''');

  // Hero: the score.
  final dash = circumference * overall / 100;
  b.write('''<section class="card hero">
<div>
<div class="eyebrow">Flutter health check</div>
<h1>${_esc(r.projectName)}</h1>
<p class="sub">${_date(r.generated)}${r.auditedWith == null ? '' : ' · checked against Flutter ${_esc(r.auditedWith!)}'}</p>
<div class="tally">
''');
  for (final s in Severity.values.where((s) => s != Severity.info)) {
    final n = r.findings.where((f) => f.severity == s).length;
    if (n > 0) {
      b.write(
        '<span class="chip sev-${s.name}">$n ${s.label.toLowerCase()}</span>\n',
      );
    }
  }
  if (r.findings.where((f) => f.severity != Severity.info).isEmpty) {
    b.write('<span class="chip g-A">no findings</span>\n');
  }
  b.write('''</div>
</div>
<div class="ring" aria-label="Overall score $overall out of 100, grade $grade">
<svg width="132" height="132" viewBox="0 0 132 132">
<circle cx="66" cy="66" r="52" fill="none" stroke="var(--line)" stroke-width="12"/>
<circle cx="66" cy="66" r="52" fill="none" stroke="var(--${grade.toLowerCase()})" stroke-width="12" stroke-linecap="round" stroke-dasharray="${dash.toStringAsFixed(1)} ${circumference.toStringAsFixed(1)}"/>
</svg>
<div class="num"><div><b class="g-$grade">$overall</b><span>grade $grade</span></div></div>
</div>
</section>
<div class="areas">
''');
  for (final a in r.areas) {
    final s = r.scoreFor(a), g = Report.grade(s);
    if (r.skipped.contains(a)) {
      b.write('''<div class="card area">
<div class="row"><span class="label">${_esc(a.label)}</span><span class="grade sev-info">–</span></div>
<div class="bar"></div>
<div class="count">not checked</div>
</div>
''');
      continue;
    }
    b.write('''<div class="card area">
<div class="row"><span class="label">${_esc(a.label)}</span><span class="grade g-$g">$g</span></div>
<div class="bar"><i class="bg-$g" style="width:$s%"></i></div>
<div class="count">$s / 100 · ${_counts(r.findings.where((f) => f.area == a))}</div>
</div>
''');
  }
  b.write('</div>\n');

  final first = r.prioritised
      .where((f) => f.severity.index <= Severity.high.index)
      .take(10)
      .toList();
  if (first.isNotEmpty) {
    b.write('<h2>Fix first</h2>\n<ol class="card first">\n');
    for (final f in first) {
      b.write(
        '<li><span class="badge sev-${f.severity.name}">${f.severity.label}</span> '
        '${_inline(f.title)} <span class="sub">· ${_esc(f.area.label)}</span></li>\n',
      );
    }
    b.write('</ol>\n');
  }

  for (final a in r.areas) {
    final list = r.prioritised.where((f) => f.area == a).toList();
    if (list.isEmpty) continue;
    final s = r.scoreFor(a), g = Report.grade(s);
    b.write(
      '<div class="area-head"><h2>${_esc(a.label)}</h2><span class="grade g-$g"><b>$s</b> · $g</span></div>\n',
    );
    for (final f in list) {
      b.write(
        '<article class="card finding sev-${f.severity.name}">\n'
        '<div class="badge">${f.severity.label}</div>\n'
        '<h3>${_inline(f.title)}</h3>\n'
        '<p>${_inline(f.detail)}</p>\n',
      );
      if (f.fix != null) {
        b.write('<p class="fix"><b>Fix:</b> ${_inline(f.fix!)}</p>\n');
      }
      if (f.locations.isNotEmpty) {
        b.write('<div class="locs">');
        for (final l in f.locations.take(10)) {
          b.write(
            l.startsWith('http')
                ? '<code><a href="${_esc(l)}">${_esc(l)}</a></code>'
                : '<code>${_esc(l)}</code>',
          );
        }
        if (f.locations.length > 10) {
          b.write(
            '<span class="sub">and ${f.locations.length - 10} more</span>',
          );
        }
        b.write('</div>\n');
      }
      b.write('<div class="id">${_esc(f.id)}</div>\n</article>\n');
    }
  }

  if (r.dependencies.isNotEmpty) {
    b.write(
      '<h2>Dependencies</h2>\n<div class="card tablewrap"><table>\n'
      '<tr><th>Package</th><th>Used by</th><th>Locked</th><th>Latest</th><th>Last release</th><th>pub points</th><th>Notes</th></tr>\n',
    );
    for (final d in r.dependencies) {
      b.write(
        '<tr><td><code>${_esc(d.name)}</code></td><td>${_esc(_kind(d.kind))}</td><td>${_esc(d.locked)}</td>'
        '<td>${_esc(d.latest ?? '')}</td>'
        '<td>${d.published == null ? '' : d.published!.toIso8601String().substring(0, 10)}</td>'
        '<td>${d.points == null ? '' : '${d.points}/${d.maxPoints}'}</td>'
        '<td>${_esc(_dependencyNote(d, r.generated))}</td></tr>\n',
      );
    }
    b.write('</table></div>\n');
  }

  b.write('<h2>Project facts</h2>\n<dl class="card facts">\n');
  for (final e in r.facts.values.entries) {
    b.write('<dt>${_esc(e.key)}</dt><dd>${_inline(e.value)}</dd>\n');
  }
  b.write('</dl>\n');

  if (r.notes.isNotEmpty) {
    b.write('<h2>Not checked</h2>\n<ul class="card plain">\n');
    for (final n in r.notes) {
      b.write('<li>${_inline(n)}</li>\n');
    }
    b.write('</ul>\n');
  }
  if (r.waived.isNotEmpty) {
    b.write('<h2>Accepted by the project</h2>\n<ul class="card plain">\n');
    for (final (f, reason) in r.waived) {
      b.write(
        '<li><span class="badge sev-${f.severity.name}">${f.severity.label}</span> '
        '${_inline(f.title)}: ${_inline(reason)} <code>${_esc(f.id)}</code></li>\n',
      );
    }
    b.write('</ul>\n');
  }

  b.write('<h2>Beyond this report</h2>\n<ul class="card plain">\n');
  for (final (title, text) in beyondThisReport) {
    b.write('<li><b>${_esc(title)}.</b> ${_inline(text)}</li>\n');
  }
  b.write('</ul>\n');
  b.write(
    '<footer>Store rules as of ${_date(r.generated)}: Google Play target API '
    '${StoreRules.playTargetSdk} (<a href="${StoreRules.playSource}">source</a>); App Store builds with '
    '${_esc(StoreRules.appStoreSdk)} (<a href="${StoreRules.appStoreSource}">source</a>). '
    'Generated by fhc.</footer>\n</main>\n</body>\n</html>\n',
  );
  return b.toString();
}
