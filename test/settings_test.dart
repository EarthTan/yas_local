import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/settings.dart';

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
}
