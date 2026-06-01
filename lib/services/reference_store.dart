import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/reference_answer.dart';

class ReferenceStore {
  static String encode(List<ReferenceAnswer> refs) =>
      jsonEncode(refs.map((r) => r.toJson()).toList());

  static List<ReferenceAnswer> decode(String raw) {
    if (raw.trim().isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => ReferenceAnswer.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<File> _file(String taskId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/reference_$taskId.json');
  }

  static Future<List<ReferenceAnswer>> load(String taskId) async {
    final f = await _file(taskId);
    if (!await f.exists()) return [];
    return decode(await f.readAsString());
  }

  static Future<void> save(String taskId, List<ReferenceAnswer> refs) async {
    final f = await _file(taskId);
    await f.writeAsString(encode(refs));
  }
}
