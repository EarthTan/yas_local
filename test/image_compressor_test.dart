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

  group('ImageCompressor.compressedPathFor — dedup & cache', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yas_imgcomp_dedup_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    Future<String> writePng(String name, int w, int h) async {
      final im = img.Image(width: w, height: h);
      im.clear(img.ColorRgb8(50, 150, 50));
      final bytes = img.encodePng(im);
      final f = File('${tmp.path}/$name.png');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    test('concurrent callers all receive the same path (smoke, not a dedup proof)', () async {
      final src = await writePng('concurrent', 2000, 1500);

      // Note: this test is a smoke test. It does not actually prove
      // that only one decode happened — 10 concurrent callers would
      // all return the same cachePath regardless of the in-flight
      // map, since the cache is keyed by srcPath. The real dedup
      // signal is the cross-process reuse test below.
      final results = await Future.wait(
        List.generate(10, (_) => ImageCompressor.compressedPathFor(src)),
      );
      final unique = results.toSet();
      expect(unique.length, 1);
      final cachePath = unique.first;
      expect(File(cachePath).existsSync(), isTrue);
    });

    test('cross-process reuse: pre-existing cache file is returned', () async {
      final src = await writePng('preexisting', 2400, 1800);
      // Pre-create the cache file so the second call must hit the
      // "file already exists" branch without invoking copyResize.
      final cachePath = ImageCompressor.cachePathFor(src);
      final placeholder = img.Image(width: 10, height: 10);
      placeholder.clear(img.ColorRgb8(0, 0, 0));
      await File(cachePath).parent.create(recursive: true);
      await File(cachePath).writeAsBytes(img.encodeJpg(placeholder));

      final result = await ImageCompressor.compressedPathFor(src);
      expect(result, cachePath);
      // The placeholder is still 10x10 — proves copyResize was not called.
      final onDisk = img.decodeImage(File(cachePath).readAsBytesSync())!;
      expect(onDisk.width, 10);
      expect(onDisk.height, 10);
    });

    test('different srcPaths produce different cache files', () async {
      final a = await writePng('a', 2000, 2000);
      final b = await writePng('b', 2000, 2000);
      final ra = await ImageCompressor.compressedPathFor(a);
      final rb = await ImageCompressor.compressedPathFor(b);
      expect(ra, isNot(rb));
    });
  });

  group('ImageCompressor.compressedPathFor — error fallback', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('yas_imgcomp_err_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('corrupted file (not an image) → returns srcPath, no throw', () async {
      final src = '${tmp.path}/not_an_image.png';
      await File(src).writeAsString('this is not a png, just bytes');
      final result = await ImageCompressor.compressedPathFor(src);
      expect(result, src);
    });

    test('empty file → returns srcPath, no throw', () async {
      final src = '${tmp.path}/empty.png';
      await File(src).writeAsBytes(<int>[]);
      final result = await ImageCompressor.compressedPathFor(src);
      expect(result, src);
    });

    test('fallback does NOT pin a completed result in _inflight (next call retries)', () async {
      // First call: file is corrupt → fallback to src.
      // Second call: overwrite with a real PNG → must succeed (i.e. the
      //   in-flight map should not have pinned a previously-failed result).
      final src = '${tmp.path}/flap.png';
      await File(src).writeAsString('garbage');
      final first = await ImageCompressor.compressedPathFor(src);
      expect(first, src);

      final im = img.Image(width: 100, height: 100);
      im.clear(img.ColorRgb8(10, 20, 30));
      await File(src).writeAsBytes(img.encodePng(im));

      final second = await ImageCompressor.compressedPathFor(src);
      expect(second, isNot(src));
      expect(File(second).existsSync(), isTrue);
    });
  });
}
