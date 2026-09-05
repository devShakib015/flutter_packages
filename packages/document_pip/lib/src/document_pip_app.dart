import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// The root of an app that can pop widgets out into their own window.
///
/// Multi-view Flutter has no single root: the engine hands you a set of views
/// and you decide what each one renders. That means `runWidget`, not `runApp`,
/// and a [ViewCollection] underneath. This is that plumbing, so the only thing
/// you write is what the two windows should show.
///
/// ```dart
/// void main() => runWidget(
///       DocumentPipApp(
///         main: (context) => const MaterialApp(home: Player()),
///         popOut: (context) => const MaterialApp(home: MiniPlayer()),
///       ),
///     );
/// ```
///
/// The first view the engine reports is the page; every later one is a
/// picture-in-picture window and gets [popOut]. Views appear and disappear as
/// windows open and close, so this rebuilds itself whenever that set changes.
class DocumentPipApp extends StatefulWidget {
  /// Creates the root.
  const DocumentPipApp({required this.main, required this.popOut, super.key});

  /// What the page itself shows.
  final WidgetBuilder main;

  /// What a picture-in-picture window shows.
  ///
  /// Built once per open window. Anything above this in the tree is shared, so
  /// state lifted above [DocumentPipApp] — a player, a socket, a store — is
  /// the same object in both windows, which is usually the point.
  final WidgetBuilder popOut;

  @override
  State<DocumentPipApp> createState() => _DocumentPipAppState();
}

class _DocumentPipAppState extends State<DocumentPipApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A view being added or removed arrives as a metrics change; there is no
  // dedicated callback for it. Without this the new window renders nothing
  // until something else happens to rebuild.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<FlutterView> views = WidgetsBinding
        .instance.platformDispatcher.views
        .toList(growable: false);
    if (views.isEmpty) return const ViewCollection(views: <Widget>[]);

    // Lowest id is the page. Ids are handed out in ascending order and the
    // page's view is added first, so this holds even after windows have opened
    // and closed and the numbering has gaps.
    final int pageViewId = views
        .map((FlutterView v) => v.viewId)
        .reduce((int a, int b) => a < b ? a : b);

    return ViewCollection(
      views: <Widget>[
        for (final FlutterView view in views)
          View(
            key: ValueKey<int>(view.viewId),
            view: view,
            child: Builder(
              builder: view.viewId == pageViewId ? widget.main : widget.popOut,
            ),
          ),
      ],
    );
  }
}
