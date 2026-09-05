import 'dart:async';

/// A picture-in-picture window that is currently open.
///
/// Hold on to this to close the window, or to know when the user closed it.
/// The [viewId] is the Flutter view the window is rendering, which is what
/// `DocumentPipApp` uses to decide what to draw there.
abstract class PipWindow {
  /// The Flutter view rendering inside this window.
  ///
  /// Matches an entry in `PlatformDispatcher.views` for as long as the window
  /// is open.
  int get viewId;

  /// Whether the window is still open.
  bool get isOpen;

  /// Completes when the window closes, however it closed — your [close] call,
  /// the user pressing the window's own close button, or the browser taking it
  /// away because another one opened.
  ///
  /// Only one picture-in-picture window can exist per browser at a time, so
  /// this is how you learn yours was displaced.
  Future<void> get closed;

  /// Closes the window and removes its Flutter view.
  ///
  /// Safe to call twice; the second call does nothing.
  Future<void> close();
}
