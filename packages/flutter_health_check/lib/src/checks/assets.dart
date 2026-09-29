import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../context.dart';
import '../model.dart';

const _images = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};

String _megabytes(int bytes) => bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).round()} KB';

/// What the app bundles: heavy images, large files, and files nothing
/// refers to.
List<Finding> checkAssets(CheckContext ctx) {
  final project = ctx.project;
  final findings = <Finding>[];
  final assets = project.declaredAssets;
  if (assets.isEmpty) {
    ctx.facts['Bundled assets'] = 'none declared';
    return findings;
  }

  var total = 0;
  final sizes = <String, int>{};
  for (final rel in assets) {
    final f = project.file(rel);
    if (!f.existsSync()) continue;
    sizes[rel] = f.lengthSync();
    total += sizes[rel]!;
  }
  ctx.facts['Bundled assets'] = '${sizes.length} files, ${_megabytes(total)}';

  final heavy = [
    for (final e in sizes.entries)
      if (_images.contains(p.extension(e.key).toLowerCase()) &&
          e.value > 500 * 1024)
        e,
  ]..sort((a, b) => b.value.compareTo(a.value));
  if (heavy.isNotEmpty) {
    final saved = heavy.fold(0, (s, e) => s + e.value);
    findings.add(
      Finding(
        id: 'assets.heavy-images',
        area: Area.assets,
        severity: Severity.low,
        title:
            '${heavy.length} image${heavy.length == 1 ? '' : 's'} over 500 KB (${_megabytes(saved)} together)',
        detail:
            '${heavy.take(5).map((e) => '${e.key} (${_megabytes(e.value)})').join(', ')}. '
            'Images this size make the download bigger and take memory to decode, even when shown '
            'small.',
        fix:
            'Resize to the largest size actually displayed (with 2x and 3x variants) and convert '
            'photos to WebP.',
        locations: [for (final e in heavy.take(10)) e.key],
      ),
    );
  }
  final bulky = [
    for (final e in sizes.entries)
      if (!_images.contains(p.extension(e.key).toLowerCase()) &&
          e.value > 5 * 1024 * 1024)
        e,
  ]..sort((a, b) => b.value.compareTo(a.value));
  if (bulky.isNotEmpty) {
    findings.add(
      Finding(
        id: 'assets.large-files',
        area: Area.assets,
        severity: Severity.medium,
        title:
            '${bulky.length == 1 ? '${bulky.single.key} adds' : '${bulky.length} files add'} '
            '${_megabytes(bulky.fold(0, (s, e) => s + e.value))} to every install',
        detail:
            '${bulky.map((e) => '${e.key} (${_megabytes(e.value)})').join(', ')}. Everything '
            'under a declared asset folder ships on every platform, whether that platform uses it '
            'or not.',
        fix:
            'Move it out of the asset folders; if one platform needs it, bundle it with that '
            'platform\'s build or download it on first use.',
        locations: [for (final e in bulky) e.key],
      ),
    );
  }
  if (total > 50 * 1024 * 1024) {
    findings.add(
      Finding(
        id: 'assets.large-bundle',
        area: Area.assets,
        severity: Severity.medium,
        title: 'Bundled assets add ${_megabytes(total)} to every install',
        detail:
            'Download size costs installs, most on slow or metered connections.',
        fix:
            'Compress what ships, and download large optional content (videos, level packs) '
            'on demand instead of bundling it.',
        locations: const ['pubspec.yaml'],
      ),
    );
  }

  // Unused: nothing in the Dart code names the file. flutter_gen hides usage
  // behind generated accessors, so skip then.
  final dev =
      (project.pubspec['dev_dependencies'] as YamlMap?)?.keys
          .map((k) => '$k')
          .toSet() ??
      {};
  if (dev.contains('flutter_gen_runner') || dev.contains('flutter_gen')) {
    ctx.notes.add(
      'The project uses flutter_gen, so unused assets were not looked for.',
    );
    return findings;
  }
  final code = [
    for (final f in project.dartFiles('lib')) f.readAsStringSync(),
  ].join('\n');
  final fonts = {
    for (final family
        in ((project.pubspec['flutter'] as YamlMap?)?['fonts'] as YamlList?) ??
            YamlList())
      for (final font
          in ((family as YamlMap)['fonts'] as YamlList?) ?? YamlList())
        p.normalize('${(font as YamlMap)['asset']}'),
  };
  final unused = <String>[];
  for (final rel in sizes.keys) {
    if (fonts.contains(rel)) continue;
    final name = p.basename(rel), stem = p.basenameWithoutExtension(rel);
    final dir = '${p.dirname(rel)}/';
    final interpolated = RegExp(
      '${RegExp.escape(dir)}[^\'"]*\\\$',
    ).hasMatch(code);
    if (interpolated ||
        code.contains(name) ||
        RegExp('\\b${RegExp.escape(stem)}\\b').hasMatch(code)) {
      continue;
    }
    unused.add(rel);
  }
  if (unused.isNotEmpty) {
    unused.sort((a, b) => sizes[b]!.compareTo(sizes[a]!));
    final bytes = unused.fold(0, (s, u) => s + sizes[u]!);
    findings.add(
      Finding(
        id: 'assets.unused',
        area: Area.assets,
        severity: Severity.low,
        title:
            '${unused.length} bundled file${unused.length == 1 ? '' : 's'} never named in the code '
            '(${_megabytes(bytes)})',
        detail:
            'No Dart file mentions ${unused.length == 1 ? 'it' : 'them'} by name: '
            '${unused.take(8).join(', ')}${unused.length > 8 ? ', …' : ''}. They still ship in '
            'every install.',
        fix: 'Check that nothing builds the path at runtime, then delete them.',
        locations: unused.take(10).toList(),
      ),
    );
  }
  return findings;
}
