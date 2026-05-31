class RubricItem {
  final int questionNumber;
  final String type; // 'objective' | 'subjective'
  final int maxPoints;
  final String? correctAnswer;
  final String questionText;
  final String criteria;

  const RubricItem({
    required this.questionNumber,
    required this.type,
    required this.maxPoints,
    this.correctAnswer,
    this.questionText = '',
    this.criteria = '',
  });

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'type': type,
        'maxPoints': maxPoints,
        'correctAnswer': correctAnswer,
        'questionText': questionText,
        'criteria': criteria,
      };

  factory RubricItem.fromJson(Map<String, dynamic> json) => RubricItem(
        questionNumber: json['questionNumber'] as int,
        type: json['type'] as String,
        maxPoints: json['maxPoints'] as int,
        correctAnswer: json['correctAnswer'] as String?,
        questionText: json['questionText'] as String? ?? '',
        criteria: json['criteria'] as String? ?? '',
      );
}
