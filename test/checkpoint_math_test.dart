import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';

void main() {
  test('CheckpointResult 分数聚合', () {
    const checkpoints = [
      CheckpointResult(description: 'A', passed: true, pointsAwarded: 2, reason: ''),
      CheckpointResult(description: 'B', passed: false, pointsAwarded: 0, reason: ''),
    ];
    final total = checkpoints.fold(0, (sum, c) => sum + c.pointsAwarded);
    expect(total, 2);
  });

  test('ReferenceAnswer checkpoint 满分汇总', () {
    const ref = ReferenceAnswer(
      questionNumber: 1,
      checkpoints: [
        CheckpointDef(id: 'q1-cp0', description: 'step1', points: 3),
        CheckpointDef(id: 'q1-cp1', description: 'step2', points: 2),
      ],
    );
    final maxPoints = ref.checkpoints.fold(0, (sum, c) => sum + c.points);
    expect(maxPoints, 5);
  });

  test('CheckpointResult 全失败总分为零', () {
    const checkpoints = [
      CheckpointResult(description: 'A', passed: false, pointsAwarded: 0, reason: '未作答'),
      CheckpointResult(description: 'B', passed: false, pointsAwarded: 0, reason: '未作答'),
    ];
    expect(checkpoints.fold(0, (sum, c) => sum + c.pointsAwarded), 0);
  });

  test('has_consensus false 不影响 ReferenceAnswer 构造', () {
    const ref = ReferenceAnswer(
      questionNumber: 2,
      checkpoints: [],
      hasConsensus: false,
    );
    expect(ref.hasConsensus, false);
    expect(ref.checkpoints, isEmpty);
  });

  test('CheckpointDef id 字段 round-trip', () {
    const cp = CheckpointDef(id: 'q1-cp0', description: '答对', points: 3);
    final round = CheckpointDef.fromJson(cp.toJson());
    expect(round.id, 'q1-cp0');
    expect(round.description, '答对');
    expect(round.points, 3);
  });

  test('CheckpointDef.fromJson 在 id 缺失时返回空字符串', () {
    final cp = CheckpointDef.fromJson({'description': '答对', 'points': 3});
    expect(cp.id, '');
  });
}
