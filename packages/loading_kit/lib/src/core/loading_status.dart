/// The visual state of the indicator at a moment in time.
enum LoadingStatus {
  /// Work is in progress. The indicator spins or tracks determinate progress.
  busy,

  /// The work completed successfully. The arc closes into a check mark.
  success,

  /// The work failed. The arc closes into a cross.
  error;

  /// Whether this status is terminal, meaning the arc has stopped spinning.
  bool get isTerminal => this != LoadingStatus.busy;
}
