/// CheckpointDef — a grading template entry on a reference answer (what points are available)
class CheckpointDef {
  final String description;
  final int points;

  const CheckpointDef({
    required this.description,
    required this.points,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'points': points,
      };

  factory CheckpointDef.fromJson(Map<String, dynamic> json) => CheckpointDef(
        description: json['description'] as String,
        points: json['points'] as int,
      );
}

/// CheckpointResult — the actual graded result for one checkpoint
class CheckpointResult {
  final String description;
  final bool passed;
  final int pointsAwarded;
  final String reason;

  const CheckpointResult({
    required this.description,
    required this.passed,
    required this.pointsAwarded,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'passed': passed,
        'pointsAwarded': pointsAwarded,
        'reason': reason,
      };

  factory CheckpointResult.fromJson(Map<String, dynamic> json) =>
      CheckpointResult(
        description: json['description'] as String,
        passed: json['passed'] as bool,
        pointsAwarded: json['pointsAwarded'] as int,
        reason: json['reason'] as String? ?? '',
      );
}
