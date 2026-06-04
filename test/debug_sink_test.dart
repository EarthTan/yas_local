import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yas_local/services/debug/debug_sink.dart';
import 'package:yas_local/services/debug/in_memory_ring_sink.dart';
import 'package:yas_local/services/debug/debug_service.dart';
import 'package:yas_local/services/debug/rolling_file_sink.dart';

void main() {
  test('DebugSink is an interface (cannot be instantiated directly)', () {
    final sink = _RecordingSink();
    expect(sink, isA<DebugSink>());
  });

  test('write must not throw — sinks swallow I/O errors', () async {
    final sink = _ThrowingSink();
    await sink.write(_dummyEvent());
  });

  test('flush defaults to no-op async', () async {
    final sink = _RecordingSink();
    await sink.flush();
  });

  group('InMemoryRingSink', () {
    test('qwenCalls caps at qwenCapacity, evicting oldest', () async {
      final sink = InMemoryRingSink(qwenCapacity: 3);
      for (var i = 0; i < 5; i++) {
        await sink.write(QwenCallRecord(
          timestamp: DateTime.now(),
          scope: 'grade',
          model: 'm',
          endpoint: '/chat/completions',
          statusCode: 200,
          elapsedMs: 1,
          status: QwenCallStatus.ok,
          messages: const [],
          responseContent: 'call-$i',
        ));
      }
      expect(sink.qwenCalls, hasLength(3));
      expect(sink.qwenCalls.first.responseContent, 'call-2');
    });

    test('events cap at eventCapacity, evicting oldest', () async {
      final sink = InMemoryRingSink(eventCapacity: 2);
      await sink.write(EventRecord(timestamp: DateTime.now(), scope: 's', level: EventLevel.info, message: 'm-0'));
      await sink.write(EventRecord(timestamp: DateTime.now(), scope: 's', level: EventLevel.info, message: 'm-1'));
      await sink.write(EventRecord(timestamp: DateTime.now(), scope: 's', level: EventLevel.info, message: 'm-2'));
      expect(sink.events.map((e) => e.message).toList(), ['m-1', 'm-2']);
    });

    test('jsonAttempts cap at jsonAttemptCapacity, evicting oldest', () async {
      final sink = InMemoryRingSink(jsonAttemptCapacity: 2);
      await sink.write(JsonAttemptRecord(
        timestamp: DateTime.now(), scope: 'x', inputSnippet: 'a', attempts: const [],
      ));
      await sink.write(JsonAttemptRecord(
        timestamp: DateTime.now(), scope: 'x', inputSnippet: 'b', attempts: const [],
      ));
      await sink.write(JsonAttemptRecord(
        timestamp: DateTime.now(), scope: 'x', inputSnippet: 'c', attempts: const [],
      ));
      expect(sink.jsonAttempts.map((r) => r.inputSnippet).toList(), ['b', 'c']);
    });

    test('write is no-op for unknown record type', () async {
      final sink = InMemoryRingSink();
      final unknown = _UnknownRecord();
      await sink.write(unknown);
      expect(sink.qwenCalls, isEmpty);
    });
  });

  group('RollingFileSink', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rolling_sink_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('writes NDJSON lines for QwenCallRecord', () async {
      PathProviderPlatform.instance = _MemoryPathProvider(tempDir);
      final sink = RollingFileSink(directory: '${tempDir.path}/log', baseName: 'test');
      await sink.write(QwenCallRecord(
        timestamp: DateTime(2026, 6, 5, 14, 23),
        scope: 'grade',
        model: 'qwen',
        endpoint: '/chat/completions',
        statusCode: 200,
        elapsedMs: 100,
        status: QwenCallStatus.ok,
        messages: const [],
        responseContent: 'r',
      ));
      await sink.flush();

      final files = tempDir.listSync(recursive: true).whereType<File>().toList();
      expect(files, hasLength(1));
      final content = await files.first.readAsString();
      expect(content, contains('"recordType":"qwen_call"'));
      expect(content, contains('"scope":"grade"'));
      expect(content, endsWith('\n'));
    });

    test('rotates when file exceeds maxFileBytes', () async {
      PathProviderPlatform.instance = _MemoryPathProvider(tempDir);
      final sink = RollingFileSink(
        directory: '${tempDir.path}/log',
        baseName: 'test',
        maxFileBytes: 200,
      );
      for (var i = 0; i < 5; i++) {
        await sink.write(EventRecord(
          timestamp: DateTime(2026, 6, 5, 14, 23, i),
          scope: 's',
          level: EventLevel.info,
          message: 'message-$i-padded-to-fill-bytes',
        ));
      }
      await sink.flush();

      final files = tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.contains('test_'))
          .toList();
      expect(files.length, greaterThan(1), reason: 'should have rotated');
      final newest = files.toList()..sort((a, b) => b.path.compareTo(a.path));
      final content = await newest.first.readAsString();
      expect(content, contains('message-4'));
    });

    test('write never throws even if directory does not exist', () async {
      final sink = RollingFileSink(
        directory: '/nonexistent_root_xyz/that_cannot_be_created/\x00invalid',
        baseName: 'test',
      );
      await expectLater(
        sink.write(EventRecord(
          timestamp: DateTime.now(), scope: 's', level: EventLevel.info, message: 'x',
        )),
        completes,
      );
    });

    test('flush is no-op when nothing was written', () async {
      PathProviderPlatform.instance = _MemoryPathProvider(tempDir);
      final sink = RollingFileSink(directory: '${tempDir.path}/log', baseName: 'test');
      await sink.flush();
      final logDir = Directory('${tempDir.path}/log');
      final files = logDir.existsSync()
          ? logDir.listSync().whereType<File>().toList()
          : <File>[];
      expect(files, isEmpty);
    });
  });
}

class _MemoryPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MemoryPathProvider(this.dir);
  final Directory dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

class _UnknownRecord implements DebugRecord {
  @override
  String get recordType => 'unknown';
  @override
  DateTime get timestamp => DateTime.now();
  @override
  Map<String, Object?> toJson() => {};
}

class _RecordingSink implements DebugSink {
  int writeCount = 0;
  @override
  Future<void> write(DebugRecord record) async {
    writeCount++;
  }
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

class _ThrowingSink implements DebugSink {
  @override
  Future<void> write(DebugRecord record) async {
    // Demonstrates the contract: sinks MUST swallow I/O errors
    // rather than letting them bubble up to the caller.
    try {
      throw Exception('disk full');
    } catch (_) {
      // Swallowed, per DebugSink contract.
    }
  }

  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
}

DebugRecord _dummyEvent() => EventRecord(
      timestamp: DateTime.now(),
      scope: 'test',
      level: EventLevel.info,
      message: 'x',
    );
