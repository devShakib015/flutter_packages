import 'dart:ui' show AppLifecycleState, FlutterView;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';

import 'document_pip.dart';

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
/// Views appear and disappear as windows open and close, so this rebuilds
/// itself whenever that set changes.
///
/// It also keeps the frame pipeline running while the tab is in the
/// background. That is not incidental: Flutter stops drawing when the page
/// reports itself hidden, and switching tabs is precisely when a pop-out is
/// the only thing the user can still see. Using this root is what keeps it
/// live; a hand-rolled [ViewCollection] will freeze instead.
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
  late Set<int> _viewIds;
  late Set<int> _popOutIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Seeded, not left empty: an empty seed makes the first metrics event
    // differ from it and rebuild for nothing, which is the thing being fixed.
    _viewIds = _currentViewIds();
    _popOutIds = DocumentPip.popOutViewIds;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static Set<int> _currentViewIds() => <int>{
        for (final FlutterView view
            in WidgetsBinding.instance.platformDispatcher.views)
          view.viewId,
      };

  // A view being added or removed arrives as a metrics change; there is no
  // dedicated callback for it. Without a rebuild the new window renders
  // nothing.
  //
  // But so does every frame of a window resize, and this package feeds that
  // loop itself — it resizes the pop-out's host element, which trips Flutter's
  // ResizeObserver. Rebuilding on the event rather than on the view set meant
  // dragging either window's edge re-ran both builders at frame rate. Each
  // View already gives its subtree its own MediaQuery, so a resize needs
  // nothing from here.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final Set<int> views = _currentViewIds();
    final Set<int> popOuts = DocumentPip.popOutViewIds;
    if (setEquals(views, _viewIds) && setEquals(popOuts, _popOutIds)) return;
    setState(() {
      _viewIds = views;
      _popOutIds = popOuts;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _keepPaintingWhileHidden(Duration.zero);

  /// Keeps frames coming while the tab is hidden and a pop-out is on screen.
  ///
  /// Chromium keeps painting a document-picture-in-picture opener at full rate
  /// even when its tab is in the background — measured at ~120fps against
  /// ~0.8fps for the same page with no pop-out open. But it still reports
  /// `visibilityState: "hidden"`, Flutter's web engine turns that into
  /// [AppLifecycleState.hidden], and `SchedulerBinding` responds by clearing
  /// `framesEnabled`, after which `scheduleFrame()` returns early forever.
  ///
  /// So without this the pop-out freezes the instant you switch tabs — in
  /// exactly the situation the window exists for. `scheduleForcedFrame()` is
  /// the documented way past that: it ignores `framesEnabled` and checks only
  /// whether a frame is already pending.
  ///
  /// A post-frame callback re-arms it, rather than a persistent one, because a
  /// persistent frame callback can never be removed and would pin this State
  /// forever. Both guards below end the loop on their own: the page coming
  /// back sets `framesEnabled`, and the last window closing empties
  /// [DocumentPip.popOutViewIds].
  void _keepPaintingWhileHidden(Duration _) {
    if (!mounted) return;
    final WidgetsBinding binding = WidgetsBinding.instance;
    if (binding.framesEnabled) return;
    if (DocumentPip.popOutViewIds.isEmpty) return;
    binding.scheduleForcedFrame();
    binding.addPostFrameCallback(_keepPaintingWhileHidden);
  }

  @override
  Widget build(BuildContext context) {
    final List<FlutterView> views = WidgetsBinding
        .instance.platformDispatcher.views
        .toList(growable: false);
    if (views.isEmpty) return const ViewCollection(views: <Widget>[]);

    // Asked, not inferred. An earlier version took the lowest view id to be
    // the page, which is wrong for any app that adds page-level views of its
    // own — add-to-app, or several Flutter hosts on one page — because every
    // host but the lowest would then render the pop-out.
    final Set<int> popOuts = DocumentPip.popOutViewIds;

    return ViewCollection(
      views: <Widget>[
        for (final FlutterView view in views)
          View(
            key: ValueKey<int>(view.viewId),
            view: view,
            child: Builder(
              builder:
                  popOuts.contains(view.viewId) ? widget.popOut : widget.main,
            ),
          ),
      ],
    );
  }
}
