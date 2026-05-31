class ObjectiveResult {
  final int score;
  final double confidence;
  const ObjectiveResult(this.score, this.confidence);
}

ObjectiveResult gradeObjectiveByKey({
  required String student,
  required String correct,
  required int maxPoints,
}) {
  final s = student.trim().toLowerCase();
  final c = correct.trim().toLowerCase();
  final match = s == c;
  return ObjectiveResult(match ? maxPoints : 0, match ? 0.97 : 0.90);
}
