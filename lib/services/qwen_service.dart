import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../models/checkpoint.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../models/settings.dart';

class OcrQuestion {
  final int number;
  final String studentAnswer;
  final String type;
  OcrQuestion(this.number, this.studentAnswer, this.type);
}

class CheckpointGrade {
  final List<CheckpointResult> checkpoints;
  final double confidence;
  final String? overallComment;
  const CheckpointGrade(this.checkpoints, this.confidence, this.overallComment);
}

class QwenService {
  final AppSettings settings;
  final Dio _dio;

  QwenService(this.settings)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(settings.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
          headers: {'Authorization': 'Bearer ${settings.apiKey}'},
        ));

  /// Users often paste the full endpoint URL from API docs
  /// (e.g. "https://api.foo.com/v1/chat/completions") instead of just the base.
  /// Strip any common endpoint suffixes so the code-appended path doesn't double up.
  static String _normalizeBaseUrl(String url) {
    url = url.trim().replaceAll(RegExp(r'/+$'), ''); // drop trailing slashes
    const knownSuffixes = ['/chat/completions', '/completions', '/embeddings'];
    for (final suffix in knownSuffixes) {
      if (url.endsWith(suffix)) {
        return url.substring(0, url.length - suffix.length);
      }
    }
    return url;
  }

  Future<List<OcrQuestion>> ocrPaper(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final b64 = base64Encode(bytes);
    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.vlModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:image/jpeg;base64,$b64'}
            },
            {
              'type': 'text',
              'text': '识别这张学生作业。抽取每道题的题号和学生作答。'
                  '只返回 JSON，不要解释：'
                  '{"questions":[{"number":int,"student_answer":string,"type":"objective|subjective"}]}'
            },
          ],
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    final parsed = _extractJson(content);
    final qs = (parsed?['questions'] as List? ?? []);
    return qs
        .map((q) => OcrQuestion(
              // Models may return number as int or string — handle both
              q['number'] is int
                  ? q['number'] as int
                  : int.tryParse(q['number'].toString()) ?? 0,
              (q['student_answer'] ?? '').toString(),
              (q['type'] ?? 'objective').toString(),
            ))
        .toList();
  }

  Future<ReferenceAnswer> generateReferenceWithAnswer(RubricItem r) async {
    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.vlModel,
      'messages': [
        {
          'role': 'user',
          'content': '你在帮老师准备评分标准。\n'
              '题目：${r.questionText}\n'
              '满分：${r.maxPoints}\n'
              '标准答案：${r.correctAnswer}\n'
              '将答案分解为评分 checkpoints（每个 checkpoint 是独立得分点），列出等价形式。\n'
              '只返回 JSON，不要解释：'
              '{"checkpoints":[{"description":string,"points":int}],'
              '"equivalent_forms":[string],"has_consensus":true}',
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    return _parseReferenceAnswer(r.questionNumber, _extractJson(content) ?? {});
  }

  Future<ReferenceAnswer> generateReferenceFromImages(
      RubricItem r, List<String> imagePaths) async {
    final imageContent = <Map<String, dynamic>>[];
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$b64'},
      });
    }

    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.vlModel,
      'messages': [
        {
          'role': 'user',
          'content': [
            ...imageContent,
            {
              'type': 'text',
              'text': '这是同一张试卷的 ${imagePaths.length} 份不同学生作业图片。\n'
                  '请仅根据印刷题目（第 ${r.questionNumber} 题，满分 ${r.maxPoints} 分）'
                  '推断正确答案，忽略学生的手写作答。\n'
                  '综合多份图片找出共识答案，分解为评分 checkpoints。\n'
                  '只返回 JSON，不要解释：'
                  '{"checkpoints":[{"description":string,"points":int}],'
                  '"equivalent_forms":[string],"has_consensus":bool}',
            },
          ],
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    return _parseReferenceAnswer(r.questionNumber, _extractJson(content) ?? {});
  }

  Future<CheckpointGrade> gradeAgainstReference({
    required RubricItem rubric,
    required ReferenceAnswer ref,
    required String studentAnswer,
  }) async {
    final checkpointLines =
        ref.checkpoints.map((c) => '- ${c.description}（${c.points}分）').join('\n');
    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.vlModel,
      'messages': [
        {
          'role': 'user',
          'content': '你在批改学生作答。\n'
              '题目：${rubric.questionText}\n'
              '满分：${rubric.maxPoints}\n'
              '评分 checkpoints：\n$checkpointLines\n'
              '学生作答：$studentAnswer\n'
              '按每个 checkpoint 判断是否通过并给分。只返回 JSON，不要解释：'
              '{"checkpoints":[{"description":string,"passed":bool,'
              '"points_awarded":int,"reason":string}],'
              '"overall_comment":string,"confidence":0.0-1.0}',
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    final json = _extractJson(content) ?? {};

    final rawList = json['checkpoints'] as List? ?? [];
    final results = rawList
        .map((c) => CheckpointResult(
              description: (c['description'] ?? '').toString(),
              passed: c['passed'] as bool? ?? false,
              pointsAwarded: (c['points_awarded'] as num?)?.toInt() ?? 0,
              reason: (c['reason'] ?? '').toString(),
            ))
        .toList();

    return CheckpointGrade(
      results,
      (json['confidence'] as num?)?.toDouble() ?? 0.8,
      json['overall_comment'] as String?,
    );
  }

  Future<Map<String, dynamic>> gradeSubjective({
    required String question,
    required String criteria,
    required int maxPoints,
    required String studentAnswer,
  }) async {
    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.textModel,
      'messages': [
        {
          'role': 'user',
          'content': '你在协助老师批改主观题。\n'
              '题目：$question\n评分标准：${criteria.isEmpty ? "（未提供，按完整度宽松评分）" : criteria}\n'
              '满分：$maxPoints\n学生作答：$studentAnswer\n'
              '只返回 JSON：{"score":int(0-$maxPoints),"comment":"一两句中文评语","confidence":0.0-1.0}'
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    return _extractJson(content) ?? {'score': 0, 'comment': '', 'confidence': 0.0};
  }

  Future<Map<String, dynamic>> judgeObjective({
    required String question,
    required String studentAnswer,
    required int maxPoints,
  }) async {
    final resp = await _dio.post('/chat/completions', data: {
      'model': settings.textModel,
      'messages': [
        {
          'role': 'user',
          'content': '判断学生这道客观题是否正确。\n题目：$question\n学生作答：$studentAnswer\n'
              '只返回 JSON：{"correct":true/false,"confidence":0.0-1.0}'
        }
      ],
    });
    final content = resp.data['choices'][0]['message']['content'] as String;
    return _extractJson(content) ?? {'correct': false, 'confidence': 0.0};
  }

  ReferenceAnswer _parseReferenceAnswer(int questionNumber, Map<String, dynamic> json) {
    final checkpoints = (json['checkpoints'] as List? ?? [])
        .map((c) => CheckpointDef(
              description: (c['description'] ?? '').toString(),
              points: (c['points'] as num?)?.toInt() ?? 1,
            ))
        .toList();
    final equivalentForms = (json['equivalent_forms'] as List? ?? [])
        .map((e) => e.toString())
        .toList();
    return ReferenceAnswer(
      questionNumber: questionNumber,
      checkpoints: checkpoints,
      equivalentForms: equivalentForms,
      hasConsensus: json['has_consensus'] as bool? ?? true,
    );
  }

  /// Strip `<think>...</think>` blocks emitted by reasoning models (Qwen3, DeepSeek-R1, etc.)
  /// before attempting JSON extraction, otherwise the first `{` lands inside the thinking block.
  String _stripThinking(String text) =>
      text.replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '').trim();

  Map<String, dynamic>? _extractJson(String text) {
    final cleaned = _stripThinking(text);
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    try {
      return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
