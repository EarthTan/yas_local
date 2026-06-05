import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:yas_local/services/debug/debug_export.dart';

class _MemoryPathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _MemoryPathProvider(this.dir);
  final Directory dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
  @override
  Future<String?> getApplicationSupportPath() async => dir.path;
}

void main() {
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('export_test_');
    PathProviderPlatform.instance = _MemoryPathProvider(tempDir);
  });
  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('writeJson creates exports dir and writes pretty JSON', () async {
    final file = await DebugExport.writeJson('test', {'hello': 'world'});
    expect(file.path, contains('/exports/test_'));
    final content = await file.readAsString();
    expect(content, contains('"hello": "world"'));
  });

  test('writeJson timestamp suffix is sortable', () async {
    final f1 = await DebugExport.writeJson('x', {'a': 1});
    await Future.delayed(const Duration(seconds: 1));
    final f2 = await DebugExport.writeJson('x', {'a': 2});
    expect(f1.path.compareTo(f2.path), lessThan(0));
  });

  test('reveal on non-macOS / non-iOS does not throw', () async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      final dummy = await DebugExport.writeJson('x', {});
      await DebugExport.reveal(dummy);
    }
  });
}
