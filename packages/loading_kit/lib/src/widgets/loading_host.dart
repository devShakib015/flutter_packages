import 'package:flutter/material.dart';

import '../core/loading_controller.dart';
import '../core/loading_global.dart';
import '../core/loading_state.dart';
import '../core/loading_timing.dart';
import '../theme/loading_style.dart';
import 'loading_overlay.dart';
import 'loading_scope.dart';

/// Installs a [LoadingController] and paints its overlay above [child].
///
/// Normally created for you by [LoadingKit.builder]. Use it directly only when
/// you need an overlay scoped to part of the app rather than the whole of it.
class LoadingHost extends StatefulWidget {
  /// Wraps [child] with a controller and an overlay.
  const LoadingHost({
    super.key,
    required this.child,
    this.controller,
    this.style = LoadingStyle.adaptive,
    this.timing = const LoadingTiming(),
    this.cancelLabel = 'Cancel',
    this.busySemanticsLabel = 'Busy',
    this.registerGlobal = true,
    this.trapFocus = true,
  });

  /// The app, or the subtree this overlay covers.
  final Widget child;

  /// An existing controller to drive. One is created and owned when null.
  final LoadingController? controller;

  /// Appearance of the overlay.
  final LoadingStyle style;

  /// Default timing policy for operations started through this host.
  ///
  /// Ignored when [controller] is supplied, since that controller carries its
  /// own policy.
  final LoadingTiming timing;

  /// Label of the cancel affordance.
  final String cancelLabel;

  /// Announced to screen readers when an operation carries no message.
  final String busySemanticsLabel;

  /// Whether to expose this host's controller through the global `Loading`.
  ///
  /// Set false for a nested or test-scoped host so it does not seize the
  /// global facade from the app's real one.
  final bool registerGlobal;

  /// Whether to pull keyboard focus out of the blocked app while busy.
  ///
  /// Without this, a hardware keyboard or a screen reader's focus can still
  /// reach buttons underneath the scrim — the overlay would look blocking
  /// without being blocking.
  final bool trapFocus;

  @override
  State<LoadingHost> createState() => _LoadingHostState();
}

class _LoadingHostState extends State<LoadingHost> {
  LoadingController? _owned;

  LoadingController get _controller => widget.controller ?? _owned!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = LoadingController(timing: widget.timing);
    }
    if (widget.registerGlobal) Loading.attach(_controller);
  }

  @override
  void didUpdateWidget(LoadingHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (widget.controller != null && _owned != null) {
        _owned!.dispose();
        _owned = null;
      } else if (widget.controller == null && _owned == null) {
        _owned = LoadingController(timing: widget.timing);
      }
      if (widget.registerGlobal) Loading.attach(_controller);
    }
  }

  @override
  void dispose() {
    if (widget.registerGlobal) Loading.detach(_controller);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `child` is passed through ValueListenableBuilder rather than captured in
    // the closure, so the app subtree is the same widget instance every frame
    // and Flutter skips rebuilding it when loading starts or stops. Only the
    // Focus wrapper above it is rebuilt.
    final Widget app = widget.trapFocus
        ? ValueListenableBuilder<LoadingState>(
            valueListenable: _controller,
            child: widget.child,
            builder: (BuildContext context, LoadingState state, Widget? child) {
              return Focus(
                canRequestFocus: false,
                descendantsAreFocusable: !state.visible,
                descendantsAreTraversable: !state.visible,
                child: child!,
              );
            },
          )
        : widget.child;

    return LoadingScope(
      controller: _controller,
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: <Widget>[
          app,
          LoadingOverlay(
            controller: _controller,
            style: widget.style,
            cancelLabel: widget.cancelLabel,
            busySemanticsLabel: widget.busySemanticsLabel,
          ),
        ],
      ),
    );
  }
}

/// Entry point for installing the overlay.
abstract final class LoadingKit {
  /// Returns a builder for [MaterialApp.builder] or [CupertinoApp.builder].
  ///
  /// This is the one line of setup the package needs:
  ///
  /// ```dart
  /// MaterialApp(
  ///   builder: LoadingKit.builder(style: LoadingStyle.glass),
  ///   navigatorObservers: [LoadingNavigatorObserver()],
  ///   home: const HomePage(),
  /// )
  /// ```
  ///
  /// Sitting above the navigator, the overlay covers every route including
  /// dialogs and sheets, and survives route transitions underneath it.
  static TransitionBuilder builder({
    LoadingStyle style = LoadingStyle.adaptive,
    LoadingTiming timing = const LoadingTiming(),
    LoadingController? controller,
    String cancelLabel = 'Cancel',
    String busySemanticsLabel = 'Busy',
    bool registerGlobal = true,
    bool trapFocus = true,
  }) {
    return (BuildContext context, Widget? child) => LoadingHost(
          controller: controller,
          style: style,
          timing: timing,
          cancelLabel: cancelLabel,
          busySemanticsLabel: busySemanticsLabel,
          registerGlobal: registerGlobal,
          trapFocus: trapFocus,
          child: child ?? const SizedBox.shrink(),
        );
  }
}
