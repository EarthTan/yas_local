import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class DebugExport {
  static Future<File> writeJson(String tab, Map<String, Object?> data) async {
    final dir = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path,
      'exports',
    ));
    if (!dir.existsSync()) await dir.create(recursive: true);
    final ts = _formatTimestamp(DateTime.now());
    final file = File(p.join(dir.path, '${tab}_$ts.json'));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  static Future<void> reveal(File file) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
    } else if (Platform.isIOS) {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'YAS debug export',
      );
    } else {
      await Clipboard.setData(ClipboardData(text: file.path));
    }
  }

  static String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$mo${d}_$h$mi$s';
  }
}
