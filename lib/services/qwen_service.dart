import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import '../models/checkpoint.dart';
import '../models/identified_question.dart';
import '../models/reference_answer.dart';
import '../models/rubric.dart';
import '../models/settings.dart';
import '../models/strategy_message.dart';
import 'debug_service.dart';
import 'image_compressor.dart';
import 'json_extractor.dart';
import 'prompts.dart';
import 'qwen_error.dart';

class QuestionGradeResult {
  final int questionNumber;
  final String extractedAnswer;
  final List<CheckpointResult> checkpoints;
  final double confidence;
  final String? overallComment;

  const QuestionGradeResult({
    required this.questionNumber,
    required this.extractedAnswer,
    required this.checkpoints,
    required this.confidence,
    this.overallComment,
  });
}

class QwenService {
  final AppSettings settings;
  final Dio _dio;
  Dio get dio => _dio;

  QwenService(this.settings)
      : _dio = Dio(BaseOptions(
          baseUrl: _normalizeBaseUrl(settings.baseUrl),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 300),
          headers: {'Authorization': 'Bearer ${settings.apiKey}'},
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final data = options.data;
        if (data is Map && data['messages'] is List) {
          options.extra['_qwen_messages'] = data['messages'] as List<Map<String, dynamic>>;
        }
        options.extra['_qwen_start'] = DateTime.now();
        handler.next(options);
      },
      onResponse: (response, handler) {
        final messages = response.requestOptions.extra['_qwen_messages'] as List<Map<String, dynamic>>?;
        final start = response.requestOptions.extra['_qwen_start'] as DateTime?;
        final choice = response.data?['choices']?[0]?['message'];
        if (messages != null && choice != null) {
          final content = choice['content'] as String? ?? '';
          final reasoning = choice['reasoning_content'] as String?;
          final elapsed = start == null ? 0 : DateTime.now().difference(start).inMilliseconds;
          DebugService.instance.recordQwenCall(QwenCallRecord(
            timestamp: start ?? DateTime.now(),
            scope: response.requestOptions.extra['_qwen_scope'] as String? ?? 'unknown',
            model: settings.vlModel,
            endpoint: response.requestOptions.path,
            statusCode: response.statusCode,
            elapsedMs: elapsed,
            status: QwenCallStatus.ok,
            messages: redactBase64Messages(messages),
            responseContent: content,
            reasoningContent: reasoning,
          ));
        }
        handler.next(response);
      },
      onError: (e, handler) {
        final messages = e.requestOptions.extra['_qwen_messages'] as List<Map<String, dynamic>>?;
        final start = e.requestOptions.extra['_qwen_start'] as DateTime?;
        final elapsed = start == null ? 0 : DateTime.now().difference(start).inMilliseconds;
        DebugService.instance.recordQwenCall(QwenCallRecord(
          timestamp: start ?? DateTime.now(),
          scope: e.requestOptions.extra['_qwen_scope'] as String? ?? 'unknown',
          model: settings.vlModel,
          endpoint: e.requestOptions.path,
          statusCode: e.response?.statusCode,
          elapsedMs: elapsed,
          status: QwenCallStatus.httpError,
          messages: messages == null ? const [] : redactBase64Messages(messages),
          errorMessage: e.message ?? '',
        ));
        handler.next(e);
      },
    ));
  }

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

  /// Returns a deep-copied [messages] list with any base64 image payloads
  /// replaced by `[redacted]`. The debug screen surfaces these messages to
  /// the teacher, so the raw image bytes must never be stored — they may
  /// contain student handwriting that we don't want to persist in clear text.
  ///
  /// Only `image_url` entries with `data:` URLs are redacted. HTTP(S) URLs
  /// (rare in this app — we always inline-encode local files) are passed
  /// through unchanged.
  static List<Map<String, dynamic>> redactBase64Messages(
      List<Map<String, dynamic>> messages) {
    return messages.map((m) {
      final content = m['content'];
      if (content is! List) return m; // text-only message: untouched
      return <String, dynamic>{
        ...m,
        'content': content.map((part) {
          if (part is! Map) return part;
          final type = part['type'];
          if (type != 'image_url') return part;
          final imageUrl = part['image_url'];
          if (imageUrl is! Map) return part;
          final url = imageUrl['url'];
          if (url is! String || !url.startsWith('data:')) return part;
          // Preserve everything before the comma (the "data:<mime>;base64,"
          // prefix) so the debug screen can still show what kind of image
          // was sent, then replace the payload.
          final commaIdx = url.indexOf(',');
          final prefix = commaIdx == -1 ? url : url.substring(0, commaIdx);
          return <String, dynamic>{
            ...part,
            'image_url': <String, dynamic>{
              ...imageUrl,
              'url': '$prefix,[redacted]',
            },
          };
        }).toList(),
      };
    }).toList();
  }

  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
  }) async {
    final imageContent = <Map<String, dynamic>>[];

    // Send question paper images first (compressed for VLM).
    final compressedQuestionPaths = await Future.wait(
      questionPaperPaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedQuestionPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    // Then optionally send answer images (compressed for VLM).
    final compressedAnswerPaths = await Future.wait(
      answerImagePaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedAnswerPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    final countCtx = totalQuestions > 0 ? '（作业共有 $totalQuestions 道题）' : '';

    final resp = await _dio.post(
      '/chat/completions',
      data: {
        'model': settings.vlModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              ...imageContent,
              {
                'type': 'text',
                'text': AppPrompts.generateStrategy(
                  questionNumber: rubricItem.questionNumber,
                  maxPoints: rubricItem.maxPoints,
                  questionText: rubricItem.questionText,
                  hasAnswerImages: answerImagePaths.isNotEmpty,
                  countCtx: countCtx,
                ),
              },
            ],
          }
        ],
      },
      options: Options(extra: {'_qwen_scope': 'strategy'}),
    );
    final content = resp.data['choices'][0]['message']['content'] as String;
    try {
      final payload = JsonExtractor.requireObjectWithReasoning(content, scope: 'strategy');
      return _parseReferenceAnswer(
        rubricItem.questionNumber,
        payload.json,
        reasoning: payload.reasoning,
      );
    } on JsonParseException catch (e) {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'strategy',
        model: settings.vlModel,
        endpoint: '/chat/completions',
        statusCode: resp.statusCode,
        elapsedMs: 0,
        status: QwenCallStatus.parseError,
        messages: const [], // already recorded by interceptor; not duplicating
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }

  Future<ReferenceAnswer> refineStrategy({
    required RubricItem rubric,
    required ReferenceAnswer current,
    required List<StrategyMessage> chatHistory,
    required String userMessage,
  }) async {
    final checkpointLines =
        current.checkpoints.map((c) => '- ${c.description}（${c.points}分）').join('\n');
    final questionLabel = rubric.questionText.isEmpty
        ? '第 ${rubric.questionNumber} 题'
        : rubric.questionText;

    // Build multi-turn messages: system context first, then prior history, then new user message
    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': AppPrompts.refineStrategySystem(
          questionLabel: questionLabel,
          maxPoints: rubric.maxPoints,
          checkpointLines: checkpointLines,
        ),
      },
      {
        'role': 'assistant',
        'content': AppPrompts.refineStrategyAssistantAck(),
      },
      for (final m in chatHistory) {'role': m.role, 'content': m.content},
      {'role': 'user', 'content': userMessage},
    ];

    final resp = await _dio.post(
      '/chat/completions',
      data: {
        'model': settings.vlModel,
        'messages': messages,
      },
      options: Options(extra: {'_qwen_scope': 'refine'}),
    );
    final content = resp.data['choices'][0]['message']['content'] as String;
    try {
      final payload = JsonExtractor.requireObjectWithReasoning(content, scope: 'refine');
      return _parseReferenceAnswer(
        current.questionNumber,
        payload.json,
        reasoning: payload.reasoning,
      );
    } on JsonParseException catch (e) {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'refine',
        model: settings.vlModel,
        endpoint: '/chat/completions',
        statusCode: resp.statusCode,
        elapsedMs: 0,
        status: QwenCallStatus.parseError,
        messages: redactBase64Messages(messages), // one-shot chat, useful to see what we sent
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }

  Future<List<IdentifiedQuestion>> identifyQuestions(List<String> imagePaths) async {
    final samples = imagePaths.length <= 3
        ? imagePaths
        : [imagePaths[0], imagePaths[imagePaths.length ~/ 2], imagePaths.last];

    final imageContent = <Map<String, dynamic>>[];
    final compressedSamples = await Future.wait(
      samples.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedSamples) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }

    final resp = await _dio.post(
      '/chat/completions',
      data: {
        'model': settings.vlModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              ...imageContent,
              {
                'type': 'text',
                'text': AppPrompts.identifyQuestions(),
              },
            ],
          }
        ],
      },
      options: Options(extra: {'_qwen_scope': 'identify'}),
    );
    final content = resp.data['choices'][0]['message']['content'] as String;
    try {
      final payload = JsonExtractor.requireListWithReasoning(content,
          fromKey: 'questions', scope: 'identify');
      // reasoning 丢弃：题型识别是中间步骤，不暴露给老师
      return payload.list
          .map((q) => IdentifiedQuestion.fromJson(q as Map<String, dynamic>))
          .toList();
    } on JsonParseException catch (e) {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'identify',
        model: settings.vlModel,
        endpoint: '/chat/completions',
        statusCode: resp.statusCode,
        elapsedMs: 0,
        status: QwenCallStatus.parseError,
        messages: const [], // already recorded by interceptor; not duplicating
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }

  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
  }) async {
    final refByNum = {for (final r in refs) r.questionNumber: r};

    final strategyLines = <String>[];
    for (final item in rubric) {
      final ref = refByNum[item.questionNumber];
      if (ref == null || ref.checkpoints.isEmpty) continue;
      final cpLines =
          ref.checkpoints.map((c) => '  - ${c.description}（${c.points}分）').join('\n');
      strategyLines.add('第${item.questionNumber}题（满分${item.maxPoints}分）：\n$cpLines');
    }
    final strategyText = strategyLines.join('\n\n');

    final imageContent = <Map<String, dynamic>>[];
    final compressedQuestionPaths = await Future.wait(
      questionPaperPaths.map(ImageCompressor.compressedPathFor),
    );
    for (final path in compressedQuestionPaths) {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      imageContent.add({
        'type': 'image_url',
        'image_url': {'url': 'data:${_mimeType(path)};base64,$b64'},
      });
    }
    // Student submission image (compressed for VLM).
    final compressedStudentPath =
        await ImageCompressor.compressedPathFor(imagePath);
    final studentBytes = await File(compressedStudentPath).readAsBytes();
    final studentB64 = base64Encode(studentBytes);
    imageContent.add({
      'type': 'image_url',
      'image_url': {'url': 'data:${_mimeType(compressedStudentPath)};base64,$studentB64'},
    });

    final resp = await _dio.post(
      '/chat/completions',
      data: {
        'model': settings.vlModel,
        'messages': [
          {
            'role': 'user',
            'content': [
              ...imageContent,
              {
                'type': 'text',
                'text': AppPrompts.gradePaper(strategyText: strategyText),
              },
            ],
          }
        ],
      },
      options: Options(extra: {'_qwen_scope': 'grade'}),
    );
    final content = resp.data['choices'][0]['message']['content'] as String;
    try {
      final payload = JsonExtractor.requireListWithReasoning(content,
          fromKey: 'questions', scope: 'grade');
      // reasoning 丢弃：批改的思考过程不暴露给学生/老师
      return payload.list.map((q) {
        final qNum = q['number'] is int
            ? q['number'] as int
            : int.tryParse(q['number'].toString()) ?? 0;
        final cps = (q['checkpoints'] as List? ?? [])
            .map((c) => CheckpointResult(
                  description: (c['description'] ?? '').toString(),
                  passed: c['passed'] as bool? ?? false,
                  pointsAwarded: (c['points_awarded'] as num?)?.toInt() ?? 0,
                  reason: (c['reason'] ?? '').toString(),
                ))
            .toList();
        return QuestionGradeResult(
          questionNumber: qNum,
          extractedAnswer: (q['extracted_answer'] ?? '').toString(),
          checkpoints: cps,
          confidence: (q['confidence'] as num?)?.toDouble() ?? 0.8,
          overallComment: q['overall_comment'] as String?,
        );
      }).toList();
    } on JsonParseException catch (e) {
      DebugService.instance.recordQwenCall(QwenCallRecord(
        timestamp: DateTime.now(),
        scope: 'grade',
        model: settings.vlModel,
        endpoint: '/chat/completions',
        statusCode: resp.statusCode,
        elapsedMs: 0,
        status: QwenCallStatus.parseError,
        messages: const [], // already recorded by interceptor; not duplicating
        errorMessage: e.toString(),
      ));
      rethrow;
    }
  }

  /// Retry policy for a single Qwen call. `bodyBuilder` is invoked on every
  /// attempt so we can append [AppPrompts.jsonRetryNudge] to the user-side
  /// text after a previous JSON parse failure. [extract] parses the response
  /// text; its thrown [JsonParseException] is what the helper treats as a
  /// JSON error. HTTP and JSON errors are wrapped in [QwenError] before
  /// rethrow. Backoff: 1000 * 2^attempt * (0.75 + rand*0.5) ms.
  ///
  /// Returns whatever [extract] returns (T).
  Future<T> _retryingRequest<T>({
    required String scope,
    required Map<String, dynamic> Function(int attempt, QwenErrorKind? lastKind)
        bodyBuilder,
    required T Function(String content) extract,
  }) async {
    const maxAttempts = 3;
    QwenErrorKind? lastKind;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final resp = await _dio.post(
          '/chat/completions',
          data: bodyBuilder(attempt, lastKind),
          options: Options(extra: {'_qwen_scope': scope}),
        );
        final content =
            resp.data['choices'][0]['message']['content'] as String;
        return extract(content);
      } catch (e) {
        final q = QwenError.from(e);
        // 4xx is a hard "stop" — no point retrying 401 / 403 / 404.
        if (!q.shouldRetry) rethrow;
        lastKind = q.kind;
        if (attempt == maxAttempts - 1) rethrow;
        final delay = _backoffMs(attempt);
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    // Unreachable: the loop either returns or rethrows. Belt-and-braces.
    throw StateError('unreachable: _retryingRequest exhausted');
  }

  int _backoffMs(int attempt) {
    // attempt 0 -> ~1s, 1 -> ~2s, 2 -> ~4s (each ±25%).
    final base = 1000 * (1 << attempt);
    final jitter = 0.75 + Random().nextDouble() * 0.5;
    return (base * jitter).round();
  }

  ReferenceAnswer _parseReferenceAnswer(
    int questionNumber,
    Map<String, dynamic> json, {
    String? reasoning,
  }) {
    final checkpoints = (json['checkpoints'] as List? ?? [])
        .asMap()
        .entries
        .map((entry) => CheckpointDef(
              id: 'q$questionNumber-cp${entry.key}',
              description: (entry.value['description'] ?? '').toString(),
              points: (entry.value['points'] as num?)?.toInt() ?? 1,
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
      reasoning: reasoning,
    );
  }

  static String _mimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => 'image/jpeg',
    };
  }

}
