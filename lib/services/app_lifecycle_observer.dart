import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/strategy_provider.dart';
import '../providers/task_provider.dart';

/// Flushes any pending debounced persistence when the app moves to the
/// background. The StrategyNotifier's 500ms edit-debounce would otherwise
/// be lost if the OS kills the process in the gap between user edit and
/// the debounce fire.
class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver(this.container);

  /// The shared [ProviderContainer] hoisted out of `ProviderScope` in
  /// `main.dart` so the observer can resolve the same notifier instances
  /// the UI sees.
  final ProviderContainer container;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      container.read(strategyProvider.notifier).flushPendingSave();
      // Also flush task state to be safe.
      container.read(taskProvider.notifier).flushPersist();
    }
  }
}
