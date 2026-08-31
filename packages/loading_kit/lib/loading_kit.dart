/// A blocking-async overlay whose thesis is timing.
///
/// ```dart
/// LoadingKit.builder(...);                       // once, in MaterialApp
/// await context.loading.run(() => api.signIn()); // anywhere with a context
/// await Loading.run(() => api.signIn());         // anywhere without one
/// ```
library;

// Exported with explicit `show` clauses rather than wholesale, so what is
// public is a decision rather than an accident. Three types that used to leak
// through — LoadingOperation, ResolvedLoadingStyle and LoadingIndicatorPainter
// — are package internals; two of them say so in their own doc comments.

export 'src/core/loading_controller.dart' show LoadingController;
export 'src/core/loading_exceptions.dart'
    show LoadingCancelled, LoadingHostMissing;
export 'src/core/loading_global.dart' show Loading;
export 'src/core/loading_handle.dart' show LoadingHandle;
export 'src/core/loading_navigator_observer.dart' show LoadingNavigatorObserver;
export 'src/core/loading_state.dart' show LoadingState;
export 'src/core/loading_status.dart' show LoadingStatus;
export 'src/core/loading_task.dart' show LoadingTask;
export 'src/core/loading_timing.dart' show LoadingTiming;
export 'src/core/loading_toast.dart' show LoadingToast;

export 'src/theme/loading_indicator_builder.dart'
    show LoadingIndicatorBuilder, LoadingIndicatorSpec;
export 'src/theme/loading_indicator_style.dart' show LoadingIndicatorStyle;
export 'src/theme/loading_motion.dart' show LoadingMotion;
export 'src/theme/loading_preset.dart' show LoadingPreset;
export 'src/theme/loading_progress_style.dart' show LoadingProgressStyle;
export 'src/theme/loading_style.dart' show LoadingStyle;
export 'src/theme/loading_toast_style.dart' show LoadingToastStyle;

export 'src/widgets/loading_barrier.dart' show LoadingBarrier;
export 'src/widgets/loading_card.dart' show LoadingCard;
export 'src/widgets/loading_host.dart' show LoadingHost, LoadingKit;
export 'src/widgets/loading_indicator.dart' show LoadingIndicator;
export 'src/widgets/loading_overlay.dart' show LoadingOverlay, LoadingStateX;
export 'src/widgets/loading_progress_bar.dart' show LoadingProgressBar;
export 'src/widgets/loading_scope.dart'
    show LoadingScope, LoadingScopeExtension;
export 'src/widgets/loading_toast_layer.dart' show LoadingToastLayer;
