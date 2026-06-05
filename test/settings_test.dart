import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/services/settings_store.dart';
import 'package:yas_local/services/debug/debug_service.dart';

void main() {
  test('默认值合理', () {
    const s = AppSettings();
    expect(s.baseUrl, 'https://dashscope.aliyuncs.com/compatible-mode/v1');
    expect(s.vlModel, 'qwen-vl-max');
    expect(s.textModel, 'qwen-plus');
    expect(s.apiKey, '');
    expect(s.isConfigured, false);
  });

  test('填了 key 后 isConfigured 为真', () {
    const s = AppSettings(apiKey: 'sk-xxx');
    expect(s.isConfigured, true);
  });

  test('JSON 往返', () {
    const s = AppSettings(apiKey: 'k', vlModel: 'qwen-vl-plus');
    expect(AppSettings.fromJson(s.toJson()).vlModel, 'qwen-vl-plus');
    expect(AppSettings.fromJson(s.toJson()).apiKey, 'k');
  });

  test('debugMode defaults to false', () {
    expect(const AppSettings().debugMode, isFalse);
  });

  test('copyWith preserves debugMode when not specified', () {
    const s = AppSettings(debugMode: true);
    expect(s.copyWith(apiKey: 'new').debugMode, isTrue);
  });

  test('copyWith overrides debugMode when specified', () {
    const s = AppSettings(debugMode: false);
    expect(s.copyWith(debugMode: true).debugMode, isTrue);
  });

  test('fromJson falls back to false when debugMode missing', () {
    final s = AppSettings.fromJson({'apiKey': 'k', 'baseUrl': 'b'});
    expect(s.debugMode, isFalse);
  });

  test('fromJson reads debugMode', () {
    final s = AppSettings.fromJson({'debugMode': true});
    expect(s.debugMode, isTrue);
  });

  test('toJson includes debugMode', () {
    const s = AppSettings(debugMode: true);
    expect(s.toJson()['debugMode'], isTrue);
  });

  group('SettingsStore I/O (H3)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('settings_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tmp.path,
      );
      DebugService.instance.resetForTest();
      DebugService.instance.setEnabled(true);
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('load returns defaults when no file exists', () async {
      final s = await SettingsStore.load();
      expect(s.apiKey, '');
      expect(s.isConfigured, isFalse);
    });

    test('save + load round-trips settings', () async {
      await SettingsStore.save(const AppSettings(apiKey: 'sk-test', vlModel: 'qwen-vl-plus'));
      final s = await SettingsStore.load();
      expect(s.apiKey, 'sk-test');
      expect(s.vlModel, 'qwen-vl-plus');
    });

    test('on corrupt settings.json: returns defaults, emits DebugService event',
        () async {
      final f = File(p.join(tmp.path, 'settings.json'));
      await f.writeAsString('garbage');
      final s = await SettingsStore.load();
      expect(s.apiKey, '');
      expect(s.isConfigured, isFalse);
      // Quarantine sibling exists.
      final siblings = tmp
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.startsWith('settings.json.broken.settings.'))
          .toList();
      expect(siblings, isNotEmpty);
      // DebugService event was emitted.
      final ev = DebugService.instance.events.single;
      expect(ev.scope, 'settings');
    });

    test('save failure (un-writable target) does not throw, but emits event',
        () async {
      // Pre-create a directory at the target path so writeJsonAtomic's
      // rename step fails (EISDIR). Pre-fix, the save would silently
      // swallow the error with no signal. Post-fix, it emits a DebugService
      // event so the failure is visible in /debug.
      final blockDir = Directory(p.join(tmp.path, 'settings.json'));
      await blockDir.create(recursive: true);
      addTearDown(() async {
        if (await blockDir.exists()) await blockDir.delete(recursive: true);
      });

      // Should not throw.
      await SettingsStore.save(const AppSettings(apiKey: 'k'));
      // But should have emitted an event.
      expect(DebugService.instance.events, isNotEmpty,
          reason: 'a save failure must emit a DebugService event');
      final ev = DebugService.instance.events.single;
      expect(ev.scope, 'settings');
      expect(ev.message, contains('save failed'));
    });
  });
}
