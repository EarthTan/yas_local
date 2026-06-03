import 'rubric.dart';

class GradingTask {
  final String id;
  final String name;
  final String subject;
  final DateTime createdAt;
  final List<RubricItem> rubric;
  final List<String> questionPaperPaths;
  final List<String> answerImagePaths;

  const GradingTask({
    required this.id,
    required this.name,
    required this.subject,
    required this.createdAt,
    required this.rubric,
    required this.questionPaperPaths,
    this.answerImagePaths = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'createdAt': createdAt.toIso8601String(),
        'rubric': rubric.map((r) => r.toJson()).toList(),
        'questionPaperPaths': questionPaperPaths,
        'answerImagePaths': answerImagePaths,
      };

  factory GradingTask.fromJson(Map<String, dynamic> json) => GradingTask(
        id: json['id'] as String,
        name: json['name'] as String,
        subject: json['subject'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        rubric: (json['rubric'] as List)
            .map((e) => RubricItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        questionPaperPaths:
            (json['questionPaperPaths'] as List?)?.cast<String>() ?? [],
        answerImagePaths:
            (json['answerImagePaths'] as List?)?.cast<String>() ?? [],
      );
}
