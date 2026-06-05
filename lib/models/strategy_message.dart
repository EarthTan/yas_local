class StrategyMessage {
  final String role; // 'user' | 'assistant'
  final String content;

  const StrategyMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory StrategyMessage.fromJson(Map<String, dynamic> json) => StrategyMessage(
        role: (json['role'] ?? 'user').toString(),
        content: (json['content'] ?? '').toString(),
      );
}
