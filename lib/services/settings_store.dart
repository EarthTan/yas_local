import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/settings.dart';

/// File-based settings storage — replaces shared_preferences to avoid
/// the CoreData/XPC crash that shared_preferences_foundation 2.5.x
/// triggers on macOS when CloudKit services are unavailable.
class SettingsStore {
  static const _fileName = 'settings.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<AppSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const AppSettings();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Return defaults on any I/O or parse error — never crash.
      return const AppSettings();
    }
  }

  static Future<void> save(AppSettings settings) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Save failure is non-fatal — settings revert to last saved value on restart.
    }
  }
}
