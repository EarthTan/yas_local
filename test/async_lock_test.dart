// Pure-Dart unit tests for AsyncLock. No Flutter binding required.

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/async_lock.dart';

void main() {
  group('AsyncLock', () {
    test('serializes two concurrent synchronized calls in submission order',
        () async {
      final lock = AsyncLock();
      final order = <int>[];

      // First body blocks on a completer so we can verify the second waits.
      final gate = Completer<void>();
      final first = lock.synchronized(() async {
        order.add(1);
        await gate.future;
        order.add(2);
      });
      // Yield so the first body has a chance to start and reach `gate.future`.
      await Future<void>.delayed(Duration.zero);
      expect(order, [1], reason: 'first body should have started');

      final second = lock.synchronized(() async {
        order.add(3);
      });

      // The second body must not have run yet.
      expect(order, [1], reason: 'second body must wait for first');

      gate.complete();
      await Future.wait([first, second]);
      expect(order, [1, 2, 3], reason: 'strict submission order');
    });

    test('one body throwing does not skip the next body', () async {
      final lock = AsyncLock();
      var secondRan = false;

      // First body throws synchronously inside the lock.
      await expectLater(
        lock.synchronized(() async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      // The next caller must still run.
      await lock.synchronized(() async {
        secondRan = true;
      });
      expect(secondRan, isTrue,
          reason: 'a failed body must not block the lock forever');
    });

    test('100 concurrent callers all serialize and all complete', () async {
      final lock = AsyncLock();
      var inFlight = 0;
      var maxInFlight = 0;
      final all = <Future<void>>[];

      for (var i = 0; i < 100; i++) {
        all.add(lock.synchronized(() async {
          inFlight++;
          if (inFlight > maxInFlight) maxInFlight = inFlight;
          // Yield so concurrent bodies can interleave if not serialized.
          await Future<void>.delayed(Duration.zero);
          inFlight--;
        }));
      }
      await Future.wait(all);
      expect(maxInFlight, 1,
          reason: 'no two bodies may be in-flight simultaneously');
      expect(inFlight, 0, reason: 'all bodies should have returned');
    });

    test('resetForTest clears pending state so subsequent runs start clean',
        () async {
      final lock = AsyncLock();
      // Schedule a long body but don't await it.
      final pending = lock.synchronized(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      // resetForTest is intentionally allowed to drop the in-flight body —
      // it's a test-only escape hatch for teardown of long-running work.
      lock.resetForTest();
      // The reset should make the next synchronized call complete promptly.
      var ran = false;
      await lock.synchronized(() async {
        ran = true;
      });
      expect(ran, isTrue);
      // Avoid an unawaited-future warning for the dropped body.
      pending.ignore();
    });
  });
}
