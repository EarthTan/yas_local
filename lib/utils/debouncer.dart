import 'dart:async';

/// Cancel-on-call debouncer: only the last call within [delay] fires.
///
/// Use for "user is dragging" patterns — UI updates fire on every change,
/// but expensive side effects (disk write, network call) should fire once
/// when the user pauses or releases.
class Debouncer {
  final Duration delay;
  Timer? _t;

  Debouncer(this.delay);

  /// Schedule [action] to run after [delay]. If called again before the
  /// timer fires, the previous call is cancelled.
  void call(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  /// Cancel any pending action. Does NOT fire the action.
  void flush() => _t?.cancel();

  /// Cancel any pending action and release the timer.
  void dispose() {
    _t?.cancel();
    _t = null;
  }
}
