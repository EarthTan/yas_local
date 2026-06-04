/// Max concurrent VLM requests per job. Kept small to stay friendly to
/// rate-limited (e.g. free-tier Qwen) accounts.
const int kMaxConcurrency = 3;

/// Runs [task] over [items] with at most [maxConcurrency] in flight at once.
///
/// Each [task] invocation receives the item and its original index. The
/// helper does NOT catch errors — a throwing task will reject the whole
/// [Future]. Callers that want per-unit isolation must wrap their task body
/// in try/catch (the JobQueue does exactly this so one failed unit never
/// aborts the batch).
///
/// Dart is single-isolate, so the `next++` cursor needs no lock.
Future<void> runPool<I>(
  List<I> items,
  int maxConcurrency,
  Future<void> Function(I item, int index) task,
) async {
  if (items.isEmpty) return;
  var next = 0;
  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= items.length) break;
      await task(items[i], i);
    }
  }

  final workers = maxConcurrency < items.length ? maxConcurrency : items.length;
  await Future.wait(List.generate(workers, (_) => worker()));
}
