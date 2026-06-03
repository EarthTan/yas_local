import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ImageStore {
  static Future<String> persist(String tempPath, String submissionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final dest = File('${imagesDir.path}/$submissionId.${_ext(tempPath)}');
    await File(tempPath).copy(dest.path);
    return dest.path;
  }

  static Future<List<String>> persistQuestionImages(
      String taskId, List<String> tempPaths) async {
    return _persistBatch(taskId, tempPaths, 'questions');
  }

  static Future<List<String>> persistAnswerImages(
      String taskId, List<String> tempPaths) async {
    return _persistBatch(taskId, tempPaths, 'answers');
  }

  static Future<List<String>> _persistBatch(
      String taskId, List<String> tempPaths, String subdir) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/images/tasks/$taskId/$subdir');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final destPaths = <String>[];
    for (var i = 0; i < tempPaths.length; i++) {
      final dest = File('${targetDir.path}/$i.${_ext(tempPaths[i])}');
      await File(tempPaths[i]).copy(dest.path);
      destPaths.add(dest.path);
    }
    return destPaths;
  }

  static String _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return 'jpg';
    final e = path.substring(dot + 1);
    return e.contains('/') ? 'jpg' : e;
  }
}
