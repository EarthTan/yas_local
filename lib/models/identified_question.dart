class IdentifiedQuestion {
  final int number;
  final String questionText;
  final String type; // 'objective' | 'subjective'

  const IdentifiedQuestion({
    required this.number,
    required this.questionText,
    this.type = 'subjective',
  });

  factory IdentifiedQuestion.fromJson(Map<String, dynamic> json) =>
      IdentifiedQuestion(
        number: json['number'] is int
            ? json['number'] as int
            : int.tryParse(json['number'].toString()) ?? 0,
        questionText: (json['text'] ?? '').toString(),
        type: const {'objective', 'subjective'}
                .contains((json['type'] ?? '').toString())
            ? json['type'] as String
            : 'subjective',
      );
}
