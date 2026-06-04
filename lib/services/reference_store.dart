import 'dart:async';
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
    // Reads are cheap and we don't have a strong ordering requirement for
    // concurrent load+save, but a chain of saves still serializes all of
    // itself via the save chain — see [_saveChain].
    final f = await _file(taskId);
    if (!await f.exists()) return [];
    return decode(await f.readAsString());
  }

  // Same shape as TaskStore._persistChain (13c9a45): coalesces parallel
  // writers (e.g. "重跑失败题" job and StrategyNotifier.saveAllConfirmed) so
  // they don't clobber the same reference_<taskId>.json.
  static Future<void> _saveChain = Future.value();

  static Future<void> save(String taskId, List<ReferenceAnswer> refs) {
    final next = _saveChain
        .then((_) async {
          final f = await _file(taskId);
          await f.writeAsString(encode(refs));
        })
        .catchError((Object e, StackTrace s) {
      _saveChain = Future.value();
      // ignore: avoid_print
      print('ReferenceStore.save failed; chain reset: $e');
      // ignore: avoid_redundant_argument_values
      Error.throwWithStackTrace(e, s);
    });
    _saveChain = next;
    return next;
  }
}
