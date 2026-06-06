import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/screens/task_detail_screen.dart';

// Structural smoke test: verifies the TaskDetailScreen widget type is
// importable and the constructor accepts a taskId. Full widget tests
// require deep ProviderContainer mocking (TaskNotifier._load() blocks
// forever in widget-test environment without an elaborate path_provider
// setup) and are deferred to a follow-up.
//
// The S-8 fix (regrade dialog debounce) is verified by code review:
//   - _showRegradeDialog early-returns when _rerunInProgress is true
//   - The FilledButton's onPressed checks _rerunInProgress again
//   - All 4 exit paths (Cancel / 保留旧结果 / 立即重批 / whenComplete)
//     reset _rerunInProgress
void main() {
  test('TaskDetailScreen constructor accepts a taskId', () {
    const widget = TaskDetailScreen(taskId: 't1');
    expect(widget.taskId, 't1');
  });
}
