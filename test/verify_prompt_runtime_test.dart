// Runtime verifier for prompt hardening (issue #3 item #2).
//
// This is NOT a unit test of AppPrompts — it drives the real
// QwenService.generateStrategy + QwenService.refineStrategy call paths
// that the running app uses, intercepts the outgoing HTTP request via
// a HttpClientAdapter mock, and dumps the actual prompt text the LLM
// would receive. Then it asserts the 硬约束 block is present and well
// formed in both prompts.
//
// Runs in the default `flutter test` sweep but is quick (~1s) and
// produces ~3 KB of prompt text. It writes a 3-byte stub JPEG to a
// temp dir — the file's content is irrelevant because the verifier
// only inspects the prompt body.
//
// ignore_for_file: avoid_print — print() is the point of this verifier
// (it dumps captured prompts to stdout for human review).
import 'dart:io';
import 'dart:math' show min;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/qwen_service.dart';

class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.responseContent);
  final String responseContent;
  final List<String> sentUserTexts = [];
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final data = options.data as Map<String, dynamic>;
    final msgs = data['messages'] as List;
    final last = msgs.last as Map;
    final content = last['content'];
    if (content is String) {
      // Multi-turn: capture the FIRST user message (the system prompt),
      // since refineStrategy's 硬约束 block lives there, not in the
      // latest user turn.
      Map? firstUser;
      for (final m in msgs) {
        final mm = m as Map;
        if (mm['role'] == 'user') {
          firstUser = mm;
          break;
        }
      }
      sentUserTexts.add(((firstUser ?? last)['content'] as String));
    } else {
      // generateStrategy: single-turn user message is a list of parts;
      // the text part is the last one (after image_url parts).
      final parts = content as List;
      final text = (parts.last as Map)['text'] as String;
      sentUserTexts.add(text);
    }
    final escaped = responseContent
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n');
    return ResponseBody.fromString(
      '{"choices":[{"message":{"content":"$escaped","role":"assistant"}}]}',
      200,
      headers: {'content-type': ['application/json']},
    );
  }
}

// Write a 3-byte file that *starts* with the JPEG magic header (FF D8 FF).
// The verifier only needs an existing path — QwenService calls
// File.readAsBytes() on it, and ImageCompressor gracefully falls back to
// the original path when its decoder returns null. So the file's actual
// pixel content is irrelevant; this is the cheapest way to make the
// full generateStrategy / refineStrategy call path execute.
Future<File> _writeFakeJpeg() async {
  final tmp = await Directory.systemTemp.createTemp('yas_verify_');
  final f = File('${tmp.path}/sample.jpg');
  await f.writeAsBytes(const [0xFF, 0xD8, 0xFF]);
  return f;
}

void main() {
  test(
    'runtime: capture and assert generateStrategy + refineStrategy prompts',
    () async {
    final settings = const AppSettings(
      apiKey: 'k',
      baseUrl: 'https://example.test/v1',
      vlModel: 'qwen-vl-max',
    );
    final svc = QwenService(settings);

    final strategyResponse =
        '{"checkpoints":[{"description":"答案合理且有依据","points":5}],'
        '"equivalent_forms":[],"has_consensus":true}';

    // === A. Drive generateStrategy end-to-end ===
    final strategyAdapter = _CapturingAdapter(strategyResponse);
    svc.dio.httpClientAdapter = strategyAdapter;
    final img1 = await _writeFakeJpeg();
    final img2 = await _writeFakeJpeg();
    final rubric = const RubricItem(
      questionNumber: 3,
      type: 'subjective',
      maxPoints: 5,
      questionText: '求 1+2+3+...+100 的和',
    );
    await svc.generateStrategy(
      rubricItem: rubric,
      questionPaperPaths: [img1.path],
      answerImagePaths: [img2.path],
      totalQuestions: 5,
    );
    expect(strategyAdapter.calls, 1,
        reason: 'expected exactly one outgoing HTTP call');
    final strategyPrompt = strategyAdapter.sentUserTexts.last;
    print('\n========== A. generateStrategy prompt (the running app\'s '
        'Phase 1 VLM call) ==========');
    print(strategyPrompt);
    print('========== END ==========\n');

    // === B. Drive refineStrategy end-to-end ===
    final refineAdapter = _CapturingAdapter(strategyResponse);
    svc.dio.httpClientAdapter = refineAdapter;
    final currentRef = ReferenceAnswer(
      questionNumber: rubric.questionNumber,
      checkpoints: const [],
    );
    await svc.refineStrategy(
      rubric: rubric,
      current: currentRef,
      chatHistory: const [],
      userMessage: '把第 2 步拆细一点',
    );
    expect(refineAdapter.calls, 1);
    final refinePrompt = refineAdapter.sentUserTexts.last;
    print('\n========== B. refineStrategy prompt (the running app\'s '
        'chat refinement call) ==========');
    print(refinePrompt);
    print('========== END ==========\n');

    // === C. Assertions on the captured prompts ===
    // generateStrategy
    expect(strategyPrompt, contains('## 硬约束'),
        reason: 'hard-constraint heading missing from generateStrategy');
    expect(strategyPrompt, contains('checkpoints 至少要有 1 项'),
        reason: '>=1 checkpoint rule missing');
    expect(strategyPrompt, contains('不能返回空数组'),
        reason: 'empty-array prohibition missing');
    expect(strategyPrompt, contains('必须恰好等于满分 5'),
        reason: 'sum-equals-maxPoints rule missing for maxPoints=5');
    expect(strategyPrompt, contains('"答案合理且有依据"'),
        reason: 'fallback checkpoint description missing');
    expect(strategyPrompt, contains('points 填 5'),
        reason: 'fallback points=5 missing');
    // The 硬约束 block should sit AFTER 字段说明 but BEFORE 输出协议,
    // so the model reads the constraints right before the output protocol
    // asks it to emit JSON. (Confirmed from the captured prompt: 硬约束
    // appears between 字段说明 and 输出协议 in the current implementation.)
    final sFieldsIdx = strategyPrompt.indexOf('字段说明');
    final sHardIdx = strategyPrompt.indexOf('## 硬约束');
    final sOutIdx = strategyPrompt.indexOf('## 输出协议');
    final sJsonIdx = strategyPrompt.indexOf('3. JSON 结构');
    expect(sFieldsIdx > 0 && sHardIdx > 0 && sOutIdx > 0 && sJsonIdx > 0,
        isTrue,
        reason: 'all four section headings must be present');
    expect(sHardIdx, greaterThan(sFieldsIdx),
        reason: '硬约束 must follow 字段说明');
    expect(sHardIdx, lessThan(sOutIdx),
        reason: '硬约束 must precede 输出协议');
    expect(sJsonIdx, greaterThan(sHardIdx),
        reason: 'JSON schema must follow the 硬约束 block');

    // refineStrategy
    expect(refinePrompt, contains('## 硬约束'));
    expect(refinePrompt, contains('checkpoints 至少要有 1 项'));
    expect(refinePrompt, contains('不能返回空数组'));
    expect(refinePrompt, contains('"答案合理且有依据"'));
    expect(refinePrompt, contains('points 填 5'));
    // 兜底措辞在两份 prompt 里应该一致：都使用"后续再迭代细化"。
    expect(strategyPrompt, contains('后续再迭代细化'),
        reason: 'generateStrategy 兜底措辞应与 refineStrategy 对齐');
    expect(refinePrompt, contains('后续再迭代细化'),
        reason: 'refineStrategy 兜底措辞应使用"后续再迭代细化"');
    expect(strategyPrompt, isNot(contains('让老师后续在策略精炼环节细化')),
        reason: '已统一措辞，不再使用"在策略精炼环节细化"');

    // === D. Probe: does the prompt survive the second pass? (json retry) ===
    // Switch adapter to return bad JSON, then good JSON. The 2nd attempt's
    // user text should be the same prompt + jsonRetryNudge (no stacking of
    // 硬约束). This protects against accidental duplication if someone
    // refactors the retry path later.
    final multi = _MultiCallAdapter(
      [ResponseBody.fromString(
          '{"choices":[{"message":{"content":"not json","role":"assistant"}}]}',
          200,
          headers: const {'content-type': ['application/json; charset=utf-8']}),
        ResponseBody.fromString(
          '{"choices":[{"message":{"content":"${
            strategyResponse.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n')
          }","role":"assistant"}}]}',
          200,
          headers: const {'content-type': ['application/json; charset=utf-8']}),
      ],
    );
    svc.dio.httpClientAdapter = multi;
    await svc.generateStrategy(
      rubricItem: rubric,
      questionPaperPaths: [img1.path],
      answerImagePaths: const [],
    );
    expect(multi.calls, 2, reason: 'expected retry on bad JSON');
    expect(multi.sentUserTexts.length, 2);
    print('\n========== D. retry probe (1st attempt vs 2nd attempt user text '
        '— should be base prompt + nudge, no duplicate 硬约束) ==========');
    print('-- 1st attempt:');
    print(multi.sentUserTexts[0]);
    print('-- 2nd attempt (last 200 chars):');
    final second = multi.sentUserTexts[1];
    print(second.length > 200 ? second.substring(second.length - 200) : second);
    print('========== END ==========\n');
    // Hard constraints should appear in BOTH attempts (carried in the base
    // prompt), but should not be duplicated within a single attempt.
    expect(multi.sentUserTexts[0], contains('## 硬约束'));
    expect(multi.sentUserTexts[1], contains('## 硬约束'));
    final hardCount1 =
        '## 硬约束'.allMatches(multi.sentUserTexts[0]).length;
    final hardCount2 =
        '## 硬约束'.allMatches(multi.sentUserTexts[1]).length;
    expect(hardCount1, 1, reason: '硬约束 must not be duplicated in attempt 1');
    expect(hardCount2, 1, reason: '硬约束 must not be duplicated in attempt 2');
  });
}

class _MultiCallAdapter implements HttpClientAdapter {
  _MultiCallAdapter(this.responses);
  final List<ResponseBody> responses;
  final List<String> sentUserTexts = [];
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data as Map<String, dynamic>;
    final msgs = data['messages'] as List;
    final last = msgs.last as Map;
    final content = last['content'];
    if (content is String) {
      Map? firstUser;
      for (final m in msgs) {
        final mm = m as Map;
        if (mm['role'] == 'user') {
          firstUser = mm;
          break;
        }
      }
      sentUserTexts.add(((firstUser ?? last)['content'] as String));
    } else {
      final parts = content as List;
      sentUserTexts.add((parts.last as Map)['text'] as String);
    }
    final r = responses[min(calls, responses.length - 1)];
    calls++;
    return r;
  }
}
