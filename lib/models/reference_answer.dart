import 'checkpoint.dart';
import 'strategy_message.dart';

class ReferenceAnswer {
  final int questionNumber;
  final List<CheckpointDef> checkpoints;
  final List<String> equivalentForms;
  final bool hasConsensus;
  final bool confirmed;
  final List<StrategyMessage> chatHistory;
  final String? reasoning;

  const ReferenceAnswer({
    required this.questionNumber,
    required this.checkpoints,
    this.equivalentForms = const [],
    this.hasConsensus = true,
    this.confirmed = false,
    this.chatHistory = const [],
    this.reasoning,
  });

  ReferenceAnswer copyWith({
    List<CheckpointDef>? checkpoints,
    List<String>? equivalentForms,
    bool? hasConsensus,
    bool? confirmed,
    List<StrategyMessage>? chatHistory,
    String? reasoning,
  }) =>
      ReferenceAnswer(
        questionNumber: questionNumber,
        checkpoints: checkpoints ?? this.checkpoints,
        equivalentForms: equivalentForms ?? this.equivalentForms,
        hasConsensus: hasConsensus ?? this.hasConsensus,
        confirmed: confirmed ?? this.confirmed,
        chatHistory: chatHistory ?? this.chatHistory,
        reasoning: reasoning ?? this.reasoning,
      );

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'equivalentForms': equivalentForms,
        'hasConsensus': hasConsensus,
        'confirmed': confirmed,
        'chatHistory': chatHistory.map((m) => m.toJson()).toList(),
        'reasoning': reasoning,
      };

  factory ReferenceAnswer.fromJson(Map<String, dynamic> json) => ReferenceAnswer(
        questionNumber: json['questionNumber'] as int,
        checkpoints: (json['checkpoints'] as List)
            .map((e) => CheckpointDef.fromJson(e as Map<String, dynamic>))
            .toList(),
        equivalentForms: (json['equivalentForms'] as List? ?? [])
            .map((e) => e as String)
            .toList(),
        hasConsensus: json['hasConsensus'] as bool? ?? true,
        confirmed: json['confirmed'] as bool? ?? false,
        chatHistory: (json['chatHistory'] as List? ?? [])
            .map((e) => StrategyMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        reasoning: json['reasoning'] as String?,
      );
}
