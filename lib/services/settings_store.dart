import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/settings.dart';
import 'atomic_io.dart';
import 'debug/debug_service.dart';

/// File-based settings storage — replaces shared_preferences to avoid
/// the CoreData/XPC crash that shared_preferences_foundation 2.5.x
/// triggers on macOS when CloudKit services are unavailable.
class SettingsStore {
  static const _fileName = 'settings.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Load the persisted settings. On a parse error, the file is
  /// quarantined (renamed aside + DebugService event) and defaults are
  /// returned, so a corrupt settings file never crashes the app and
  /// never silently loses the user's API key without a trace.
  static Future<AppSettings> load() async {
    final f = await _file();
    return readJsonOrQuarantine<AppSettings>(
      f,
      _decode,
      () => const AppSettings(),
      scope: 'settings',
    );
  }

  static AppSettings _decode(Object? parsed) {
    if (parsed is Map<String, dynamic>) return AppSettings.fromJson(parsed);
    if (parsed is Map) return AppSettings.fromJson(parsed.cast<String, dynamic>());
    return const AppSettings();
  }

  /// Save [settings] to disk. Failures are NOT thrown — the caller UI
  /// already shows a success SnackBar unconditionally — but a DebugService
  /// event is emitted so the failure is visible in /debug.
  static Future<void> save(AppSettings settings) async {
    try {
      final f = await _file();
      await writeJsonAtomic(f, jsonEncode(settings.toJson()));
    } catch (e) {
      await DebugService.instance.recordEvent(
        scope: 'settings',
        level: EventLevel.error,
        message: 'persist: settings save failed',
        data: {
          'error': e.toString().length > 500
              ? '${e.toString().substring(0, 500)}…'
              : e.toString(),
        },
      );
    }
  }
}
