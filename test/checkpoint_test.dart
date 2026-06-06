import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';

void main() {
  test('CheckpointDef.fromJson returns empty description when missing', () {
    final cp = CheckpointDef.fromJson({'points': 3});
    expect(cp.description, '');
    expect(cp.points, 3);
  });
  test('CheckpointDef.fromJson returns 0 points when missing', () {
    final cp = CheckpointDef.fromJson({'description': 'X'});
    expect(cp.points, 0);
  });
}
