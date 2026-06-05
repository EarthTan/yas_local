/// Central repository for all LLM prompt templates.
/// Dynamic values are passed as named parameters; Dart interpolation handles substitution.
class AppPrompts {
  AppPrompts._();

  /// Appended to the system text on a retry caused by a JSON parse failure,
  /// so the model gets a fresh chance to emit clean JSON. Same wording on every
  /// retry — never stacked.
  static const String jsonRetryNudge =
      '\n\n注意：上一次返回的内容无法解析为 JSON，请只返回纯 JSON，不要任何解释或 <think> 内容。';

  /// Shared output protocol used by all 4 LLM calls. Each call appends its
  /// own step 3 (the expected JSON schema) after this prefix.
  ///
  /// [thinkingHints] is an optional sub-bullet appended under step 1, used
  /// by `generateStrategy` to nudge the model toward useful thinking.
  static String _outputProtocol({String? thinkingHints}) {
    final hints = thinkingHints == null
        ? ''
        : '   $thinkingHints\n';
    return '## 输出协议（必须严格遵守）\n'
        '1. 先用 <thinking>...</thinking> 标签写下你的思考过程'
        '（不要在 thinking 内放 JSON）。\n'
        '$hints'
        '2. thinking 之后**直接**输出一个 JSON 对象，'
        '不要用 ```json``` 围栏，不要任何前后解释。\n';
  }

  // ── 识别题目 ────────────────────────────────────────────────────────────────

  static String identifyQuestions() =>
      '请识别这份试卷中的所有题目。\n'
      '列出每道题的题号、题目内容、以及题型。\n'
      '\n'
      '字段说明：\n'
      '- number：题号，按试卷印刷顺序从 1 开始编号。\n'
      '- text：题目的完整原文。如果题目是选择题，也需要包含所有选项；\n'
      '- type：题型——objective 表示选择题、判断题、填空题等有唯一正确答案的题型；'
      'subjective 表示简答题、论述题、计算题等需要人工评判的题型。\n'
      '\n'
      '要求：如果同一道题包含多个小题（如 3.(1)、3.(2)），'
      '作为一个题目处理，text 中包含全部小题内容。\n'
      '\n'
      '${_outputProtocol()}'
      '3. JSON 结构：{"questions":[{"number":int,"text":string,"type":"objective|subjective"}]}';

  // ── 生成评分策略 ───────────────────────────────────────────────────────────────

  static String generateStrategy({
    required int questionNumber,
    required int maxPoints,
    required String questionText,
    required bool hasAnswerImages,
    String answerContext = '',
    String countCtx = '',
  }) =>
      '你正在帮老师准备评分标准$countCtx。\n'
      '请先查看以上题目图片，理解第 $questionNumber 题的内容和要求。\n'
      '满分：$maxPoints 分\n'
      '题目内容：$questionText\n'
      '${hasAnswerImages ? '以上图片中包含了教师的参考答案，请据此制定评分标准。\n' : '请根据题目内容推断正确答案并制定评分标准。\n'}'
      '将预期的解答分解为评分 checkpoints（每个 checkpoint 是独立得分点），列出等价形式。\n'
      '\n'
      '字段说明：\n'
      '- checkpoints：评分点列表，所有 checkpoints 的 points 之和必须等于满分 $maxPoints。如果是只有结果没有过程的客观题（例如选择题，填空题），则只返回一个checkpoint核对结果是否正确即可。\n'
      '  - description：该评分点的内容描述，要求清晰可判断学生是否达标。\n'
      '  - points：该评分点的分值，整数。\n'
      '- equivalent_forms：等价答案列表。\n'
      '- has_consensus：本题答案是否有公认标准（有明确唯一解填 true，开放型论述题填 false）。\n'
      '\n'
      '## 硬约束（违反其中任何一条都会让老师无法批改，请仔细遵守）\n'
      '- checkpoints 至少要有 1 项，不能返回空数组 `[]`。\n'
      '- 所有 checkpoints 的 points 之和必须恰好等于满分 $maxPoints。\n'
      '- 如果你拿不准如何拆解步骤（例如题目太开放、无法明确得分点），'
      '仍然必须返回 1 个 checkpoint：description 写"答案合理且有依据"，points 填 $maxPoints，'
      '后续再迭代细化。绝对不允许因为"不好拆"就返回空。\n'
      '\n'
      '${_outputProtocol(thinkingHints: '思考要点：本题考查的知识点 → 完整解答的关键步骤 → 学生常见失分点。')}'
      '3. JSON 结构：{"checkpoints":[{"description":string,"points":int}],'
      '"equivalent_forms":[string],"has_consensus":bool}';

  // ── 策略精炼（多轮对话） ───────────────────────────────────────────────────

  /// 首条系统角色消息（以 user 角色发送，模拟 system）
  static String refineStrategySystem({
    required String questionLabel,
    required int maxPoints,
    required String checkpointLines,
  }) =>
      '你在帮老师修改题目的批改策略。\n'
      '题目：$questionLabel\n'
      '满分：$maxPoints\n'
      '当前批改 checkpoints：\n$checkpointLines\n'
      '老师会提出修改要求，请根据要求更新 checkpoints 并返回完整的新策略。\n'
      '\n'
      '字段说明（注意：所有 checkpoints 的 points 之和必须等于满分 $maxPoints）：\n'
      '- checkpoints：更新后的评分点列表。\n'
      '  - description：评分点描述。\n'
      '  - points：分值（整数），总和必须等于 $maxPoints。\n'
      '- equivalent_forms：等价答案列表。\n'
      '- has_consensus：是否有公认标准答案。\n'
      '\n'
      '## 硬约束（违反其中任何一条都会让老师无法批改，请仔细遵守）\n'
      '- checkpoints 至少要有 1 项，不能返回空数组 `[]`。\n'
      '- 所有 checkpoints 的 points 之和必须恰好等于满分 $maxPoints。\n'
      '- 如果你拿不准如何拆解步骤（例如老师想改成开放型、尚未明确得分点），'
      '仍然必须返回 1 个 checkpoint：description 写"答案合理且有依据"，points 填 $maxPoints，'
      '后续再迭代细化。绝对不允许因为"不好拆"就返回空。\n'
      '\n'
      '${_outputProtocol()}'
      '3. JSON 结构：{"checkpoints":[{"description":string,"points":int}],'
      '"equivalent_forms":[string],"has_consensus":bool}';

  /// 紧随 system 消息之后的 assistant 确认语，用于建立多轮对话上下文
  static String refineStrategyAssistantAck() =>
      '好的，我已了解当前批改策略。请告诉我您希望如何修改。';

  // ── 批改试卷 ───────────────────────────────────────────────────────────────

  static String gradePaper({required String strategyText}) =>
      '请参考附带的试卷原题图片，批改这份学生作业中的全部题目。评分标准如下：\n\n'
      '$strategyText\n\n'
      '对每道题，先提取学生的手写作答，然后按评分 checkpoints 逐条判断。\n'
      '\n'
      '{"questions":[{"number":int,"extracted_answer":string,'
      '"checkpoints":[{"description":string,"passed":bool,'
      '"points_awarded":int,"reason":string}],'
      '"overall_comment":string,"confidence":0.0-1.0}]}\n'
      '\n'
      '字段说明：\n'
      '- number：题号，与评分标准中的题号对应。\n'
      '- extracted_answer：从图片中提取的学生手写作答原文，逐字转录，不做纠错或改写。'
      '如果学生留空未答，填空字符串 ""。\n'
      '- checkpoints：按评分标准逐项评判的结果，每个对应评分标准中的一个 checkpoint。\n'
      '  - description：该 checkpoint 的描述，与评分标准保持一致。\n'
      '  - passed：学生是否达到了该评分点的要求（完全达标为 true，部分达标或未达标为 false）。\n'
      '    注意：passed 只区分"完全达标"与"未完全达标"，部分得分通过 points_awarded 体现。\n'
      '  - points_awarded：该评分点实际得分，可以是 0 到该 checkpoint 满分之间的任意整数。'
      '学生完全答对得满分，部分正确给部分分，完全错误给 0 分。\n'
      '  - reason：评分理由，用一句话说明为什么给这个分数'
      '（如"概念正确但未写出反应条件，扣 1 分"）。\n'
      '- overall_comment：整道题的评语，指出学生的整体表现和主要失分点，用于反馈给学生。\n'
      '- confidence：整道题评分的置信度，0.0-1.0 之间的浮点数。'
      '≥0.85 为高置信度（答案清晰、评分类别明确），'
      '≥0.60 为中等置信度，'
      '<0.60 为低置信度（手写潦草、答案含糊、主观判断多），需要教师复核。\n'
      '\n'
      '${_outputProtocol()}'
      '3. JSON 结构：{"questions":[{"number":int,"extracted_answer":string,'
      '"checkpoints":[{"description":string,"passed":bool,'
      '"points_awarded":int,"reason":string}],'
      '"overall_comment":string,"confidence":0.0-1.0}]}';
}
