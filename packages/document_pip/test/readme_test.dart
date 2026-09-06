// Every API call the README makes, compiled. A snippet checker only catches
// syntax; this catches a signature that has drifted, which is the failure that
// actually reaches readers.
import 'package:document_pip/document_pip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the README root compiles and runs', (WidgetTester t) async {
    await t.pumpWidget(
      DocumentPipApp(
        main: (BuildContext context) => const MaterialApp(home: Player()),
        popOut: (BuildContext context) => const MaterialApp(home: MiniPlayer()),
      ),
      wrapWithView: false,
    );
    await t.pumpAndSettle();
    expect(find.text('player'), findsOneWidget);
  });

  test('the README calls exist with the types it shows', () async {
    expect(DocumentPip.isSupported, isA<bool>());
    expect(DocumentPip.current, isA<PipWindow?>());

    // Named arguments and their types, exactly as the README writes them.
    final Future<PipWindow> opening = DocumentPip.open(
      width: 380,
      height: 210,
      copyStyles: true,
      disallowReturnToOpener: false,
      preferInitialWindowPlacement: false,
    );
    await expectLater(opening, throwsA(isA<DocumentPipException>()));
  });

  test('the README error handling compiles and is exhaustive', () {
    String handle(DocumentPipException e) => switch (e) {
          DocumentPipUnsupported() => 'unsupported',
          DocumentPipNotBootstrapped() => 'bootstrap',
          final DocumentPipDenied e => e.message,
        };
    expect(handle(const DocumentPipUnsupported()), 'unsupported');
  });

  test('PipWindow exposes what the README says it does', () {
    // Compile-time only: names and types the README promises on the handle.
    // Named rather than `_`: wildcard variables are Dart 3.7 and this package
    // declares a 3.5 floor, so they would not compile at its own minimum.
    void uses(PipWindow w) {
      final int id = w.viewId;
      final bool open = w.isOpen;
      final Future<void> done = w.closed;
      final Future<void> closing = w.close();
      expect(<Object>[id, open, done, closing], hasLength(4));
    }

    expect(uses, isA<void Function(PipWindow)>());
  });
}

class Player extends StatelessWidget {
  const Player({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('player')));
}

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('mini')));
}
