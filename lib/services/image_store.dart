import 'dart:io';
import 'package:path_provider/path_provider.dart';

class ImageStore {
  static Future<String> persist(String tempPath, String submissionId) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final ext = tempPath.contains('.') ? tempPath.split('.').last : 'jpg';
    final dest = File('${imagesDir.path}/$submissionId.$ext');
    await File(tempPath).copy(dest.path);
    return dest.path;
  }

  static Future<List<String>> persistQuestionImages(
      String taskId, List<String> tempPaths) async {
    final dir = await getApplicationDocumentsDirectory();
    final questionsDir =
        Directory('${dir.path}/images/tasks/$taskId/questions');
    if (!await questionsDir.exists()) {
      await questionsDir.create(recursive: true);
    }
    final destPaths = <String>[];
    for (var i = 0; i < tempPaths.length; i++) {
      final tempPath = tempPaths[i];
      final ext = tempPath.contains('.') ? tempPath.split('.').last : 'jpg';
      final dest = File('${questionsDir.path}/$i.$ext');
      await File(tempPath).copy(dest.path);
      destPaths.add(dest.path);
    }
    return destPaths;
  }

  static Future<List<String>> persistAnswerImages(
      String taskId, List<String> tempPaths) async {
    final dir = await getApplicationDocumentsDirectory();
    final answersDir = Directory('${dir.path}/images/tasks/$taskId/answers');
    if (!await answersDir.exists()) {
      await answersDir.create(recursive: true);
    }
    final destPaths = <String>[];
    for (var i = 0; i < tempPaths.length; i++) {
      final tempPath = tempPaths[i];
      final ext = tempPath.contains('.') ? tempPath.split('.').last : 'jpg';
      final dest = File('${answersDir.path}/$i.$ext');
      await File(tempPath).copy(dest.path);
      destPaths.add(dest.path);
    }
    return destPaths;
  }
}
