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
  // Set by StrategyNotifier when loading a cached reference whose
  // questionNumber is no longer present in the task's rubric (i.e. the
  // teacher removed that question after generation). The reference is kept
  // on disk for grading integrity, but the UI surfaces a banner so the
  // teacher knows the 0-point render is meaningless.
  final bool missingFromRubric;

  const ReferenceAnswer({
    required this.questionNumber,
    required this.checkpoints,
    this.equivalentForms = const [],
    this.hasConsensus = true,
    this.confirmed = false,
    this.chatHistory = const [],
    this.reasoning,
    this.missingFromRubric = false,
  });

  ReferenceAnswer copyWith({
    List<CheckpointDef>? checkpoints,
    List<String>? equivalentForms,
    bool? hasConsensus,
    bool? confirmed,
    List<StrategyMessage>? chatHistory,
    String? reasoning,
    bool? missingFromRubric,
  }) =>
      ReferenceAnswer(
        questionNumber: questionNumber,
        checkpoints: checkpoints ?? this.checkpoints,
        equivalentForms: equivalentForms ?? this.equivalentForms,
        hasConsensus: hasConsensus ?? this.hasConsensus,
        confirmed: confirmed ?? this.confirmed,
        chatHistory: chatHistory ?? this.chatHistory,
        reasoning: reasoning ?? this.reasoning,
        missingFromRubric: missingFromRubric ?? this.missingFromRubric,
      );

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'equivalentForms': equivalentForms,
        'hasConsensus': hasConsensus,
        'confirmed': confirmed,
        'chatHistory': chatHistory.map((m) => m.toJson()).toList(),
        'reasoning': reasoning,
        'missingFromRubric': missingFromRubric,
      };

  factory ReferenceAnswer.fromJson(Map<String, dynamic> json) {
    final qn = json['questionNumber'] as int;
    final raw = ((json['checkpoints'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(CheckpointDef.fromJson)
        .toList();
    final checkpoints = [
      for (var i = 0; i < raw.length; i++)
        raw[i].id.isEmpty
            ? raw[i].copyWith(id: 'q$qn-cp$i')
            : raw[i],
    ];
    return ReferenceAnswer(
      questionNumber: qn,
      checkpoints: checkpoints,
      equivalentForms: ((json['equivalentForms'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      hasConsensus: json['hasConsensus'] as bool? ?? true,
      confirmed: json['confirmed'] as bool? ?? false,
      chatHistory: ((json['chatHistory'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(StrategyMessage.fromJson)
          .toList(),
      reasoning: json['reasoning'] as String?,
      missingFromRubric: json['missingFromRubric'] as bool? ?? false,
    );
  }
}
