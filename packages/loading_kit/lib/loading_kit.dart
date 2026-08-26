/// A blocking-async overlay that never flickers.
///
/// Wrap any future in one call and the overlay handles delayed reveal,
/// minimum display time, reference counting, route awareness, cancellation
/// and accessibility:
///
/// ```dart
/// MaterialApp(
///   builder: LoadingKit.builder(),
///   navigatorObservers: [LoadingNavigatorObserver()],
///   home: const HomePage(),
/// );
///
/// final user = await Loading.run(
///   () => api.signIn(email, password),
///   message: 'Signing in…',
///   successMessage: 'Welcome back',
/// );
/// ```
library;

export 'src/core/loading_controller.dart';
export 'src/core/loading_exceptions.dart';
export 'src/core/loading_global.dart';
export 'src/core/loading_handle.dart';
export 'src/core/loading_navigator_observer.dart';
export 'src/core/loading_state.dart';
export 'src/core/loading_status.dart';
export 'src/core/loading_task.dart';
export 'src/core/loading_timing.dart';
export 'src/core/loading_toast.dart';
export 'src/theme/loading_indicator_builder.dart';
export 'src/theme/loading_indicator_style.dart';
export 'src/theme/loading_preset.dart';
export 'src/theme/loading_progress_style.dart';
export 'src/theme/loading_style.dart';
export 'src/theme/resolved_loading_style.dart';
export 'src/widgets/loading_barrier.dart';
export 'src/widgets/loading_card.dart';
export 'src/widgets/loading_host.dart';
export 'src/widgets/loading_indicator.dart';
export 'src/widgets/loading_overlay.dart';
export 'src/widgets/loading_progress_bar.dart';
export 'src/widgets/loading_scope.dart';
export 'src/widgets/loading_toast_layer.dart';
