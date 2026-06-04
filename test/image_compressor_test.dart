import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:yas_local/services/image_compressor.dart';

void main() {
  group('ImageCompressor._cachePathFor naming rules', () {
    test('submission image: stem passes through, suffix becomes .jpg', () {
      expect(
        ImageCompressor.cachePathFor('/tmp/docs/images/abc123.jpg'),
        endsWith('/images/compressed/abc123.jpg'),
      );
    });

    test('question paper image: subdir parts joined with _', () {
      expect(
        ImageCompressor.cachePathFor(
          '/tmp/docs/images/tasks/t1/questions/0.png',
        ),
        endsWith('/images/compressed/t1_questions_0.jpg'),
      );
    });

    test('answer image: subdir parts joined with _', () {
      expect(
        ImageCompressor.cachePathFor(
          '/tmp/docs/images/tasks/t1/answers/1.jpeg',
        ),
        endsWith('/images/compressed/t1_answers_1.jpg'),
      );
    });

    test('PNG input still produces .jpg output (unified format)', () {
      final out = ImageCompressor.cachePathFor('/x/images/sub.png');
      expect(p.extension(out), '.jpg');
    });
  });

  group('ImageCompressor.compressedPathFor', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yas_imgcomp_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('returns srcPath when src does not exist (fallback, no throw)', () async {
      final missing = '${tmp.path}/does_not_exist.png';
      final result = await ImageCompressor.compressedPathFor(missing);
      expect(result, missing);
    });
  });

  group('ImageCompressor.compressedPathFor — decode/resize/encode', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yas_imgcomp_rt_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<String> writePng(int w, int h) async {
      // Use the project's image package to build a deterministic PNG.
      final im = img.Image(width: w, height: h);
      im.clear(img.ColorRgb8(200, 200, 200));
      final bytes = img.encodePng(im);
      final f = File('${tmp.path}/in_${w}x$h.png');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    test('decodes a real PNG, writes JPEG to cache, returns cache path', () async {
      final src = await writePng(100, 100);
      final result = await ImageCompressor.compressedPathFor(src);
      expect(result, isNot(src));
      expect(File(result).existsSync(), isTrue);
      // First two bytes of a JPEG are 0xFF 0xD8.
      final head = await File(result).openRead(0, 2).toList();
      expect(head.first, [0xFF, 0xD8]);
    });

    test('3200x2400 input → cache image longest edge ≤ 1600, aspect kept', () async {
      final src = await writePng(3200, 2400);
      final cachePath = await ImageCompressor.compressedPathFor(src);
      final out = img.decodeImage(File(cachePath).readAsBytesSync())!;
      expect(out.width, 1600);
      expect(out.height, 1200);
    });

    test('800x600 input is upscaled to longest edge 1600 (uniform rule)', () async {
      final src = await writePng(800, 600);
      final cachePath = await ImageCompressor.compressedPathFor(src);
      final out = img.decodeImage(File(cachePath).readAsBytesSync())!;
      expect(out.width, 1600);
      expect(out.height, 1200);
    });

    test('square 1500x1500 → 1600x1600', () async {
      final src = await writePng(1500, 1500);
      final cachePath = await ImageCompressor.compressedPathFor(src);
      final out = img.decodeImage(File(cachePath).readAsBytesSync())!;
      expect(out.width, 1600);
      expect(out.height, 1600);
    });
  });
}
