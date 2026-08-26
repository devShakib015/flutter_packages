import 'package:flutter/widgets.dart';

import '../core/loading_controller.dart';

/// Provides a [LoadingController] to a subtree.
///
/// Installed by `LoadingKit.builder`. Because the controller's identity never
/// changes, dependents are not rebuilt when loading starts or stops — anything
/// that wants to react listens to the controller itself.
class LoadingScope extends InheritedWidget {
  /// Provides [controller] to [child].
  const LoadingScope({
    super.key,
    required this.controller,
    required super.child,
  });

  /// The controller made available to descendants.
  final LoadingController controller;

  /// Returns the nearest controller, or null when none is installed.
  static LoadingController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LoadingScope>()
      ?.controller;

  /// Returns the nearest controller, asserting that one exists.
  static LoadingController of(BuildContext context) {
    final LoadingController? controller = maybeOf(context);
    assert(
      controller != null,
      'No LoadingScope found. Add LoadingKit.builder() to MaterialApp.builder, '
      'or wrap this subtree in a LoadingScope of your own.',
    );
    return controller!;
  }

  @override
  bool updateShouldNotify(LoadingScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Sugar for reaching the nearest [LoadingController].
extension LoadingScopeExtension on BuildContext {
  /// The nearest controller: `context.loading.run(...)`.
  LoadingController get loading => LoadingScope.of(this);

  /// The nearest controller, or null when none is installed.
  LoadingController? get maybeLoading => LoadingScope.maybeOf(this);
}
