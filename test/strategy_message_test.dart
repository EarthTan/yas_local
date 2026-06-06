import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/strategy_message.dart';

void main() {
  test('StrategyMessage.fromJson tolerates missing content', () {
    final m = StrategyMessage.fromJson({'role': 'user'});
    expect(m.role, 'user');
    expect(m.content, '');
  });
}
