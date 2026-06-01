import 'checkpoint.dart';

class ReferenceAnswer {
  final int questionNumber;
  final List<CheckpointDef> checkpoints;
  final List<String> equivalentForms;
  final bool hasConsensus;

  const ReferenceAnswer({
    required this.questionNumber,
    required this.checkpoints,
    this.equivalentForms = const [],
    this.hasConsensus = true,
  });

  Map<String, dynamic> toJson() => {
        'questionNumber': questionNumber,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'equivalentForms': equivalentForms,
        'hasConsensus': hasConsensus,
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
      );
}
