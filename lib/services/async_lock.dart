import 'dart:async';

/// A simple async mutex that serializes FIFO.
///
/// Each [synchronized] call enqueues a body that runs after the previous
/// body's future has settled. Errors propagate to the awaiting caller; the
/// next caller is *not* skipped.
///
/// In single-isolate Dart this is the right tool for serializing async I/O
/// (file writes, network calls) where order matters but locking a thread
/// is meaningless. NOT safe for re-entrancy: if [body] itself calls
/// [synchronized] on the same [AsyncLock], it will deadlock.
///
/// Lifted from the private `_Lock` in `rolling_file_sink.dart` (which
/// retains a private copy pending a follow-up migration).
class AsyncLock {
  Future<void> _last = Future.value();

  /// Run [body] after all previously-enqueued bodies have settled.
  /// Returns the result of [body], or rethrows whatever [body] threw.
  Future<T> synchronized<T>(Future<T> Function() body) {
    final completer = Completer<T>();
    final prev = _last;
    // Strip errors so a rejected `_last` doesn't block the next caller.
    // Errors are still surfaced to the original caller via `completer.future`.
    _last = completer.future.then((_) {}, onError: (_) {});
    prev.whenComplete(() async {
      try {
        completer.complete(await body());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Test-only escape hatch: drop any pending work so the next
  /// [synchronized] runs immediately. The dropped body's future is left
  /// dangling; callers should `ignore()` it. Do not call from production.
  void resetForTest() {
    _last = Future.value();
  }
}
