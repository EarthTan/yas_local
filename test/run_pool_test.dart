import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/run_pool.dart';

void main() {
  test('runs every item exactly once, preserving index', () async {
    final seen = <int>[];
    await runPool([10, 20, 30], 2, (item, index) async {
      seen.add(index);
    });
    seen.sort();
    expect(seen, [0, 1, 2]);
  });

  test('never exceeds maxConcurrency in flight', () async {
    var inFlight = 0;
    var peak = 0;
    await runPool(List.generate(10, (i) => i), 3, (item, index) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
    });
    expect(peak, lessThanOrEqualTo(3));
  });

  test('empty list completes without invoking task', () async {
    var calls = 0;
    await runPool(<int>[], 3, (item, index) async => calls++);
    expect(calls, 0);
  });

  test('a throwing task does not abort siblings (caller must catch)', () async {
    final done = <int>[];
    await runPool([0, 1, 2], 3, (item, index) async {
      try {
        if (item == 1) throw Exception('boom');
        done.add(item);
      } catch (_) {
        // swallow — mirrors how JobQueue wraps each unit
      }
    });
    done.sort();
    expect(done, [0, 2]);
  });
}
