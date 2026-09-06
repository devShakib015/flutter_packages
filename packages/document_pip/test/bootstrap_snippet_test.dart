@TestOn('vm')
library;

// The bootstrap is the hardest step in using this package, and there are three
// copies of it: README.md, the DocumentPipNotBootstrapped message a stuck
// developer reaches at runtime, and example/web/flutter_bootstrap.js — the only
// one that has ever actually been run.
//
// They drifted. Before this test the runtime message said
// `hostElement: document.body`, which the engine treats as a custom-element
// host: it CLEARS the host's children (wiping the page, script tags included)
// and sizes the view to 100% of an auto-height body, i.e. nothing. It was the
// one configuration never shipped and never tested, and it was the copy handed
// to whoever was already stuck.
//
// Reads files, so it needs the package root; `flutter test` runs from there.
import 'dart:io';

import 'package:document_pip/document_pip.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `app.addView({...})` line, normalised for whitespace.
String? addViewLine(String source) {
  for (final String line in source.split('\n')) {
    if (line.contains('app.addView(')) {
      return line.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
  }
  return null;
}

void main() {
  final String readme = File('README.md').readAsStringSync();
  final String runtime = const DocumentPipNotBootstrapped().message;
  final File bootstrapFile = File('example/web/flutter_bootstrap.js');

  test('all three copies of the bootstrap add the view the same way', () {
    final String? fromReadme = addViewLine(readme);
    final String? fromRuntime = addViewLine(runtime);

    expect(fromReadme, isNotNull, reason: 'README lost its addView line');
    expect(
      fromRuntime,
      isNotNull,
      reason: 'the error message lost its snippet',
    );
    expect(
      fromRuntime,
      fromReadme,
      reason: 'the message a stuck developer reads must match the README',
    );

    // The example is the only copy that has been executed, so it is the
    // reference. It is gitignored in every other package as generated
    // scaffolding; here it is hand-written and deliberately tracked.
    expect(
      bootstrapFile.existsSync(),
      isTrue,
      reason:
          'example/web/flutter_bootstrap.js must ship — it is not '
          'scaffolding, and without it the published example cannot run',
    );
    expect(addViewLine(bootstrapFile.readAsStringSync()), fromReadme);
  });

  test('no copy of the snippet hosts a view on document.body', () {
    // Not style. CustomElementEmbeddingStrategy calls hostElement.clearChildren()
    // and attachViewRoot sizes the root to height:100%, so document.body empties
    // the page and then measures zero — a blank screen and no exception.
    for (final MapEntry<String, String> copy in <String, String>{
      'README.md': readme,
      'DocumentPipNotBootstrapped': runtime,
      'example bootstrap': bootstrapFile.existsSync()
          ? bootstrapFile.readAsStringSync()
          : '',
    }.entries) {
      expect(
        addViewLine(copy.value) ?? '',
        isNot(contains('document.body')),
        reason: '${copy.key} tells the user to wipe their own page',
      );
    }
  });

  test('the runtime message still carries everything it promises', () {
    // The README calls this message "the exact snippet", so it has to be
    // self-contained: the loader config, the handover, and the host element
    // the addView line points at.
    expect(runtime, contains('multiViewEnabled'));
    expect(runtime, contains('window.documentPipApp'));
    expect(runtime, contains('runWidget'));
    expect(runtime, contains('id="app"'));
  });
}
