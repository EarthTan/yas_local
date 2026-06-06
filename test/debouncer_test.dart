import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('action fires once after the delay when called rapidly', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      for (var i = 0; i < 5; i++) {
        d(() => calls++);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 1);
    });

    test('flush cancels pending action', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      d(() => calls++);
      d.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });

    test('dispose cancels pending action', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      d(() => calls++);
      d.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });
  });
}
