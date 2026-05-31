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
}
