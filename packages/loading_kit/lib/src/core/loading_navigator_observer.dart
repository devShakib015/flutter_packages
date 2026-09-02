import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'loading_controller.dart';
import 'loading_global.dart';

/// Retires overlays when the route beneath them changes.
///
/// Without this, an overlay started on one screen can outlive it — the classic
/// symptom being a spinner stuck over a screen that never asked for it, with
/// no way to dismiss. Add it to your navigator:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [LoadingNavigatorObserver()],
///   builder: LoadingKit.builder(),
/// )
/// ```
///
/// Operations created with `dismissOnNavigation: false` are left alone, for
/// the rare job that should legitimately span a route change.
class LoadingNavigatorObserver extends NavigatorObserver {
  /// Watches [controller], or the global controller when none is given.
  LoadingNavigatorObserver({this.controller});

  /// The controller to clear. Defaults to whatever `Loading` is attached to.
  final LoadingController? controller;

  LoadingController? get _target =>
      controller ?? (Loading.isInstalled ? Loading.instance : null);

  void _clear() {
    // Under the pages API, didPush lands inside the build phase — Navigator
    // updates its routes while building — and dismissAll mutates a
    // ValueNotifier the overlay listens to, so clearing inline threw
    // "setState() or markNeedsBuild() called during build". Deferring to
    // after the frame keeps the behaviour and drops the crash. Runs inline
    // when nothing is building, so an imperative push still clears promptly.
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      unawaited(
        _target?.dismissAll(immediate: true, onlyNavigationScoped: true),
      );
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _target?.dismissAll(immediate: true, onlyNavigationScoped: true),
      );
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _clear();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _clear();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _clear();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _clear();
}
