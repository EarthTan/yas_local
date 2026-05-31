import 'rubric.dart';

class GradingTask {
  final String id;
  final String name;
  final String subject;
  final DateTime createdAt;
  final List<RubricItem> rubric;

  const GradingTask({
    required this.id,
    required this.name,
    required this.subject,
    required this.createdAt,
    required this.rubric,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subject': subject,
        'createdAt': createdAt.toIso8601String(),
        'rubric': rubric.map((r) => r.toJson()).toList(),
      };

  factory GradingTask.fromJson(Map<String, dynamic> json) => GradingTask(
        id: json['id'] as String,
        name: json['name'] as String,
        subject: json['subject'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        rubric: (json['rubric'] as List)
            .map((e) => RubricItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
