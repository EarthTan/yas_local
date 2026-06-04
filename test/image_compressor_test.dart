import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
