import 'dart:async';
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
import 'debug/debug_service.dart';
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
    void Function(int attempt)? onAttempt,
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
    final userText = AppPrompts.generateStrategy(
      questionNumber: rubricItem.questionNumber,
      maxPoints: rubricItem.maxPoints,
      questionText: rubricItem.questionText,
      hasAnswerImages: answerImagePaths.isNotEmpty,
      countCtx: countCtx,
    );

    return _retryingRequest<ReferenceAnswer>(
      scope: 'strategy',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireObjectWithReasoning(
          content,
          scope: 'strategy',
        );
        return _parseReferenceAnswer(
          rubricItem.questionNumber,
          payload.json,
          reasoning: payload.reasoning,
        );
      },
      onAttempt: onAttempt,
    );
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
    final baseMessages = <Map<String, dynamic>>[
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

    // Lightweight one-shot retry: if the first response fails JSON parsing,
    // re-send with the new user turn appended with jsonRetryNudge. We don't
    // go through _retryingRequest because the multi-turn message structure
    // doesn't match its bodyBuilder contract.
    for (var attempt = 0; attempt < 2; attempt++) {
      final messages = attempt == 0
          ? baseMessages
          : <Map<String, dynamic>>[
              ...baseMessages.sublist(0, baseMessages.length - 1),
              {
                'role': 'user',
                'content': userMessage + AppPrompts.jsonRetryNudge,
              },
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
        if (attempt == 1) rethrow;
      }
    }
    // Unreachable: the loop either returns or rethrows.
    throw StateError('unreachable: refineStrategy retry loop exhausted');
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

    final userText = AppPrompts.identifyQuestions();

    return _retryingRequest<List<IdentifiedQuestion>>(
      scope: 'identify',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireListWithReasoning(
          content,
          fromKey: 'questions',
          scope: 'identify',
        );
        // reasoning 丢弃：题型识别是中间步骤，不暴露给老师
        return payload.list
            .map((q) => IdentifiedQuestion.fromJson(q as Map<String, dynamic>))
            .toList();
      },
    );
  }

  Future<List<QuestionGradeResult>> gradePaper({
    required String imagePath,
    required List<String> questionPaperPaths,
    required List<RubricItem> rubric,
    required List<ReferenceAnswer> refs,
    void Function(int attempt)? onAttempt,
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

    final userText = AppPrompts.gradePaper(strategyText: strategyText);

    return _retryingRequest<List<QuestionGradeResult>>(
      scope: 'grade',
      bodyBuilder: (attempt, lastKind) {
        final text = lastKind == QwenErrorKind.jsonParse
            ? userText + AppPrompts.jsonRetryNudge
            : userText;
        return {
          'model': settings.vlModel,
          'messages': [
            {
              'role': 'user',
              'content': [...imageContent, {'type': 'text', 'text': text}],
            },
          ],
        };
      },
      extract: (content) {
        final payload = JsonExtractor.requireListWithReasoning(
          content,
          fromKey: 'questions',
          scope: 'grade',
        );
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
      },
      onAttempt: onAttempt,
    );
  }

  /// Retry policy for a single Qwen call. `bodyBuilder` is invoked on every
  /// attempt so we can append [AppPrompts.jsonRetryNudge] to the user-side
  /// text after a previous JSON parse failure. [extract] parses the response
  /// text; its thrown [JsonParseException] is what the helper treats as a
  /// JSON error. HTTP and JSON errors are wrapped in [QwenError] before
  /// rethrow. Backoff: 1000 * 2^attempt * (0.75 + rand*0.5) ms.
  ///
  /// [onAttempt] (optional) is invoked synchronously at the start of each
  /// loop iteration with the 0-indexed attempt number (0, 1, 2). It is the
  /// caller's responsibility to translate this to a 1-based label for UI.
  /// It is intended for progress reporting (e.g. JobQueueNotifier updating
  /// JobState.attempt) and is called BEFORE the network request, so the
  /// observed value reflects an attempt that is *about* to fire, not one
  /// that has finished.
  ///
  /// Returns whatever [extract] returns (T).
  Future<T> _retryingRequest<T>({
    required String scope,
    required Map<String, dynamic> Function(int attempt, QwenErrorKind? lastKind)
        bodyBuilder,
    required T Function(String content) extract,
    void Function(int attempt)? onAttempt,
  }) async {
    const maxAttempts = 3;
    QwenErrorKind? lastKind;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      onAttempt?.call(attempt);
      try {
        final resp = await _dio.post(
          '/chat/completions',
          data: bodyBuilder(attempt, lastKind),
          options: Options(extra: {'_qwen_scope': scope}),
        );
        // Split the cast into two statements so `content` is in scope
        // in the catch — the single-statement form does NOT bind
        // `content` if the RHS cast throws on a null/missing body.
        final rawContent = resp.data['choices'][0]['message']['content'];
        final content = rawContent as String;
        return extract(content);
      } catch (e) {
        final q = QwenError.from(e);
        // 4xx is a hard "stop" — no point retrying 401 / 403 / 404.
        if (!q.shouldRetry) throw q;
        lastKind = q.kind;
        if (attempt == maxAttempts - 1) {
          // Last attempt failed. Record a parseError summary so the
          // Debug screen's JSON 解析 tab is useful (without this, all
          // 3 attempts show up as "ok" because the Dio interceptor
          // records per HTTP outcome, not per parse outcome). The
          // record is fire-and-forget: matching the interceptor's
          // pattern, so a record-side failure cannot replace the
          // original QwenError in the throw chain.
          if (q.kind == QwenErrorKind.jsonParse ||
              // Empty/missing body surfaces as a TypeError on the
              // `as String` cast; functionally a parse failure. The
              // errorMessage field on the record preserves the
              // original TypeError so a teacher can distinguish it
              // from a JSON decode failure in the Debug screen.
              (q.kind == QwenErrorKind.unknown && e is TypeError)) {
            // Fire-and-forget — see the interceptor's recordQwenCall
            // pattern. A record-side failure must not replace the
            // original QwenError in the throw chain.
            _recordParseError(
              scope: scope,
              bodyBuilder: bodyBuilder,
              attempt: attempt,
              lastKind: lastKind,
              content: e is JsonParseException ? e.rawContent : null,
              error: e,
            ).ignore();
          }
          throw q;
        }
        final delay = _backoffMs(attempt);
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
    }
    // Unreachable: the loop either returns or rethrows. Belt-and-braces.
    throw StateError('unreachable: _retryingRequest exhausted');
  }

  Future<void> _recordParseError({
    required String scope,
    required Map<String, dynamic> Function(int attempt, QwenErrorKind? lastKind)
        bodyBuilder,
    required int attempt,
    required QwenErrorKind? lastKind,
    required String? content,
    required Object error,
  }) {
    final body = bodyBuilder(attempt, lastKind);
    List<Map<String, dynamic>> messages;
    final raw = body['messages'];
    if (raw is List) {
      messages = raw.whereType<Map<String, dynamic>>().toList();
    } else {
      messages = const [];
    }
    return DebugService.instance.recordQwenCall(QwenCallRecord(
      timestamp: DateTime.now(),
      scope: scope,
      model: settings.vlModel,
      endpoint: '/chat/completions',
      statusCode: 200,
      elapsedMs: 0,
      status: QwenCallStatus.parseError,
      messages: redactBase64Messages(messages),
      responseContent: content ?? '',
      errorMessage: error.toString(),
    ));
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
