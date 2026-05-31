class GradedItem {
  final int questionNumber;
  final String type;
  final String? extractedAnswer;
  final int? aiScore;
  final String? aiComment;
  final double? confidence;
  final int? teacherScore;

  const GradedItem({
    required this.questionNumber,
    required this.type,
    this.extractedAnswer,
    this.aiScore,
    this.aiComment,
    this.confidence,
    this.teacherScore,
  });

  int get finalScore => teacherScore ?? aiScore ?? 0;

  String get trafficLight {
    final c = confidence ?? 0.0;
    if (c >= 0.85) return 'green';
    if (c >= 0.60) return 'yellow';
    return 'red';
  }

  GradedItem copyWith({int? teacherScore}) => GradedItem(
        questionNumber: questionNumber,
        type: type,
        extractedAnswer: extractedAnswer,
        aiScore: aiScore,
        aiComment: aiComment,
        confidence: confidence,
        teacherScore: teacherScore ?? this.teacherScore,
      );

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'type': type,
        'extractedAnswer': extractedAnswer,
        'aiScore': aiScore,
        'aiComment': aiComment,
        'confidence': confidence,
        'teacherScore': teacherScore,
      };

  factory GradedItem.fromJson(Map<String, dynamic> json) => GradedItem(
        questionNumber: json['questionNumber'] as int,
        type: json['type'] as String,
        extractedAnswer: json['extractedAnswer'] as String?,
        aiScore: json['aiScore'] as int?,
        aiComment: json['aiComment'] as String?,
        confidence: (json['confidence'] as num?)?.toDouble(),
        teacherScore: json['teacherScore'] as int?,
      );
}

enum SubmissionStatus { pending, processing, done, failed }

class Submission {
  final String id;
  final String taskId;
  final String label;
  final String? imagePath;
  final SubmissionStatus status;
  final List<GradedItem> items;

  const Submission({
    required this.id,
    required this.taskId,
    required this.label,
    this.imagePath,
    this.status = SubmissionStatus.pending,
    this.items = const [],
  });

  int get computedTotal => items.fold(0, (sum, i) => sum + i.finalScore);
  int get pendingReviewCount =>
      items.where((i) => i.type == 'subjective' && i.teacherScore == null).length;

  Submission copyWith({
    SubmissionStatus? status,
    List<GradedItem>? items,
    String? imagePath,
  }) =>
      Submission(
        id: id,
        taskId: taskId,
        label: label,
        imagePath: imagePath ?? this.imagePath,
        status: status ?? this.status,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'taskId': taskId,
        'label': label,
        'imagePath': imagePath,
        'status': status.name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Submission.fromJson(Map<String, dynamic> json) => Submission(
        id: json['id'] as String,
        taskId: json['taskId'] as String,
        label: json['label'] as String,
        imagePath: json['imagePath'] as String?,
        status: SubmissionStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => SubmissionStatus.pending,
        ),
        items: (json['items'] as List? ?? [])
            .map((e) => GradedItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
