import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/debug_service.dart';
import 'package:yas_local/services/json_extractor.dart';

void main() {
  // ── requireObject ──────────────────────────────────────────────────────────

  group('JsonExtractor.requireObject', () {
    test('裸 JSON 对象文本', () {
      final result = JsonExtractor.requireObject('{"key": "value", "num": 42}');
      expect(result['key'], 'value');
      expect(result['num'], 42);
    });

    test('JSON 包在 ```json``` 围栏内', () {
      const text = '好的，评分标准如下：\n```json\n{"checkpoints": [{"description": "正确", "points": 4}]}\n```\n请确认。';
      final result = JsonExtractor.requireObject(text);
      expect(result['checkpoints'], isA<List>());
      expect((result['checkpoints'] as List).first['points'], 4);
    });

    test('JSON 包在无语言标注的 ``` 围栏内', () {
      const text = '```\n{"a": 1}\n```';
      final result = JsonExtractor.requireObject(text);
      expect(result['a'], 1);
    });

    test('<think> 块在 JSON 前被剥离', () {
      const text = '<think>让我思考一下……</think>\n{"answer": "B"}';
      final result = JsonExtractor.requireObject(text);
      expect(result['answer'], 'B');
    });

    test('多个围栏时取第一个可解析的', () {
      // 第一个围栏 JSON 无效，第二个合法
      const text = '```json\n{broken\n```\n```json\n{"ok": true}\n```';
      final result = JsonExtractor.requireObject(text);
      expect(result['ok'], true);
    });

    test('无围栏时退回到全文括号匹配', () {
      const text = '这是结果：{"has_consensus": false, "equivalent_forms": []}，请使用。';
      final result = JsonExtractor.requireObject(text);
      expect(result['has_consensus'], false);
    });

    test('嵌套对象正确解析', () {
      const text = '```json\n{"outer": {"inner": 99}}\n```';
      final result = JsonExtractor.requireObject(text);
      expect((result['outer'] as Map)['inner'], 99);
    });

    test('完全无效内容 → 抛出 JsonParseException', () {
      expect(
        () => JsonExtractor.requireObject('这里根本没有 JSON'),
        throwsA(isA<JsonParseException>()),
      );
    });

    test('空字符串 → 抛出 JsonParseException', () {
      expect(
        () => JsonExtractor.requireObject(''),
        throwsA(isA<JsonParseException>()),
      );
    });

    test('JsonParseException 携带原始内容', () {
      const raw = '完全乱码 xyz';
      try {
        JsonExtractor.requireObject(raw);
        fail('应该 throw');
      } on JsonParseException catch (e) {
        expect(e.rawContent, raw);
        expect(e.message, isNotEmpty);
      }
    });
  });

  // ── requireList ────────────────────────────────────────────────────────────

  group('JsonExtractor.requireList', () {
    test('裸 JSON 数组', () {
      final result = JsonExtractor.requireList('[1, 2, 3]');
      expect(result, [1, 2, 3]);
    });

    test('数组包在 ```json``` 围栏内', () {
      const text = '```json\n[{"number": 1}, {"number": 2}]\n```';
      final result = JsonExtractor.requireList(text);
      expect(result.length, 2);
      expect(result.first['number'], 1);
    });

    test('fromKey：对象格式 {"questions": [...]}', () {
      const text = '{"questions": [{"n": 1}, {"n": 2}], "total": 2}';
      final result = JsonExtractor.requireList(text, fromKey: 'questions');
      expect(result.length, 2);
      expect(result.first['n'], 1);
    });

    test('fromKey 指定但文本是裸数组时 fallback 到裸数组', () {
      const text = '[{"n": 1}]';
      final result = JsonExtractor.requireList(text, fromKey: 'questions');
      expect(result.length, 1);
      expect(result.first['n'], 1);
    });

    test('fromKey 值不是 List 时 fallback 到裸数组提取', () {
      // fromKey 存在但值是字符串，不是 list → 继续向下找裸数组
      const text = '{"questions": "not a list"}\n[{"fallback": true}]';
      final result = JsonExtractor.requireList(text, fromKey: 'questions');
      expect(result.first['fallback'], true);
    });

    test('围栏内的对象格式 + fromKey', () {
      const text = '批改结果：\n```json\n{"questions": [{"number": 3, "extracted_answer": "C"}]}\n```';
      final result = JsonExtractor.requireList(text, fromKey: 'questions');
      expect(result.first['number'], 3);
      expect(result.first['extracted_answer'], 'C');
    });

    test('围栏内的裸数组 + fromKey fallback', () {
      const text = '```json\n[{"number": 1, "extracted_answer": "A"}]\n```';
      final result = JsonExtractor.requireList(text, fromKey: 'questions');
      expect(result.first['number'], 1);
    });

    test('<think> 块剥离后找到数组', () {
      const text = '<think>逐题分析……</think>\n[{"n": 5}]';
      final result = JsonExtractor.requireList(text);
      expect(result.first['n'], 5);
    });

    test('多个围栏时取第一个可解析的', () {
      const text = '```json\nnot valid\n```\n```json\n[{"ok": true}]\n```';
      final result = JsonExtractor.requireList(text);
      expect(result.first['ok'], true);
    });

    test('完全无效内容 → 抛出 JsonParseException', () {
      expect(
        () => JsonExtractor.requireList('没有任何数组'),
        throwsA(isA<JsonParseException>()),
      );
    });

    test('JsonParseException 携带原始内容', () {
      const raw = '乱码 abc';
      try {
        JsonExtractor.requireList(raw);
        fail('应该 throw');
      } on JsonParseException catch (e) {
        expect(e.rawContent, raw);
      }
    });
  });

  // ── requireObjectWithReasoning ────────────────────────────────────────────

  group('JsonExtractor.requireObjectWithReasoning', () {
    test('<think> 块 + 后续 JSON：拆出 reasoning 和 json', () {
      const text = '<think>考查一元二次方程求根公式的应用。</think>\n'
          '{"checkpoints":[{"description":"判别式正确","points":3}]}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '考查一元二次方程求根公式的应用。');
      expect((payload.json['checkpoints'] as List).first['points'], 3);
    });

    test('无 thinking 块时 reasoning 为 null', () {
      const text = '{"checkpoints":[{"points":2}]}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, isNull);
      expect((payload.json['checkpoints'] as List).first['points'], 2);
    });

    test('<thinking> 块同样被识别', () {
      const text = '<thinking>本题为客观题，只核对答案。</thinking>\n'
          '{"checkpoints":[{"description":"答案正确","points":1}]}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '本题为客观题，只核对答案。');
      expect((payload.json['checkpoints'] as List).first['points'], 1);
    });

    test('大小写不敏感', () {
      const text = '<THINKING>全大写也认</THINKING>\n{"k":1}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '全大写也认');
      expect(payload.json['k'], 1);
    });

    test('thinking 块跨多行', () {
      const text = '<think>\n第一行\n第二行\n第三行\n</think>\n{"k":"v"}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '第一行\n第二行\n第三行');
      expect(payload.json['k'], 'v');
    });

    test('thinking 块内容含 JSON-like 字符不干扰提取', () {
      const text = '<think>看到 {curly} 和 [bracket] 不影响</think>{"real":true}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '看到 {curly} 和 [bracket] 不影响');
      expect(payload.json['real'], true);
    });

    test('多块时只取第一个 thinking 块', () {
      const text = '<thinking>第一个思考</thinking>中间文本<thinking>第二个</thinking>{"k":1}';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '第一个思考');
      expect(payload.json['k'], 1);
    });

    test('thinking 块内文含围栏不影响', () {
      const text = '<think>参考 ```code``` 块</think>\n```json\n{"k":1}\n```';
      final payload = JsonExtractor.requireObjectWithReasoning(text);
      expect(payload.reasoning, '参考 ```code``` 块');
      expect(payload.json['k'], 1);
    });
  });

  // ── requireListWithReasoning ───────────────────────────────────────────────

  group('JsonExtractor.requireListWithReasoning', () {
    test('<think> 块 + 数组：拆出 reasoning 和 list', () {
      const text = '<think>逐题思考中…</think>\n[{"number":1},{"number":2}]';
      final payload = JsonExtractor.requireListWithReasoning(text);
      expect(payload.reasoning, '逐题思考中…');
      expect(payload.list.length, 2);
      expect(payload.list.first['number'], 1);
    });

    test('无 thinking 块时 reasoning 为 null', () {
      const text = '[1,2,3]';
      final payload = JsonExtractor.requireListWithReasoning(text);
      expect(payload.reasoning, isNull);
      expect(payload.list, [1, 2, 3]);
    });

    test('fromKey 也工作：对象格式', () {
      const text = '<thinking>先看题</thinking>\n{"questions":[{"n":1}]}';
      final payload = JsonExtractor.requireListWithReasoning(text, fromKey: 'questions');
      expect(payload.reasoning, '先看题');
      expect(payload.list.first['n'], 1);
    });
  });

  // ── DebugService instrumentation ───────────────────────────────────────────

  group('DebugService instrumentation', () {
    setUp(() {
      DebugService.instance.resetForTest();
      DebugService.instance.setEnabled(true);
    });

    test('successful extraction records an attempt', () {
      JsonExtractor.requireObject('{"a": 1}');
      expect(DebugService.instance.jsonAttempts, hasLength(1));
      expect(DebugService.instance.jsonAttempts.single.attempts.last.ok, isTrue);
    });

    test('failed extraction records attempts including the failing branch and finalException', () {
      try {
        JsonExtractor.requireObject('this is not json');
      } catch (_) {}
      expect(DebugService.instance.jsonAttempts, hasLength(1));
      final r = DebugService.instance.jsonAttempts.single;
      expect(r.attempts.where((a) => a.ok), isNotEmpty); // strip_thinking succeeded
      expect(r.attempts.where((a) => !a.ok), isNotEmpty); // braces_object failed
      expect(r.finalException, isNotNull);
    });
  });
}
