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
        CheckpointDef(description: 'step1', points: 3),
        CheckpointDef(description: 'step2', points: 2),
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
}
