import 'dart:async';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'debug/debug_service.dart';

/// Longest-edge clamp for VLM-facing images. Qwen VL scales inputs down
/// internally; overshooting 1600 wastes bandwidth with no quality win.
const int _kMaxEdge = 1600;

/// JPEG re-encode quality. 85 is the standard "visually lossless" sweet spot
/// for hand-written exam content; lower visibly degrades red marks.
const int _kJpegQuality = 85;

/// VLM image preprocessing — compress to JPEG, longest edge ≤ 1600px,
/// cached in `<docs>/images/compressed/`. Idempotent, in-flight deduplicated,
/// silently falls back to the original path on any failure.
class ImageCompressor {
  ImageCompressor._();

  /// Process-wide cache: same `srcPath` shared across concurrent callers
  /// only triggers one decode. Stored via a `Completer` so we can tell
  /// whether a previous attempt is still in flight (dedup) or already
  /// resolved (re-evaluate, in case the previous attempt fell back).
  static final Map<String, Completer<String>> _inflight = {};

  /// Compute the on-disk cache path for [srcPath]. Naming rule: the
  /// relative path under `images/` (excluding the `images/` segment
  /// itself) is taken, slashes are replaced with `_`, and the suffix is
  /// forced to `.jpg`. Exposed for tests; not part of the public surface
  /// that `QwenService` depends on.
  static String cachePathFor(String srcPath) {
    // Normalize and split on `images/`. Anything before is dropped; the
    // remainder (e.g. `tasks/t1/questions/0.png` or `sub123.jpg`) becomes
    // the stem.
    final normalized = p.normalize(srcPath);
    final marker = '${Platform.pathSeparator}images${Platform.pathSeparator}';
    final idx = normalized.indexOf(marker);
    final rel = idx == -1
        ? p.basename(normalized)
        : normalized.substring(idx + marker.length);
    // Drop the leading `tasks/` segment if present (it's a fixed type
    // prefix used by ImageStore, not part of the per-image identity).
    final relNoTypePrefix = rel.startsWith('tasks${Platform.pathSeparator}')
        ? rel.substring('tasks'.length + 1)
        : rel;
    final stem = relNoTypePrefix.replaceAll(Platform.pathSeparator, '_');
    final noExt = p.withoutExtension(stem);
    final cacheDir = idx == -1
        ? p.join(p.dirname(normalized), 'images', 'compressed')
        : p.join(
            normalized.substring(0, idx),
            'images',
            'compressed',
          );
    return p.join(cacheDir, '$noExt.jpg');
  }

  /// Returns the path of a compressed copy of [srcPath], creating it on
  /// first call and reusing the cache on subsequent calls (in-process and
  /// cross-process). On any failure returns [srcPath] unchanged.
  ///
  /// A second call after a failed compress re-attempts the work — the
  /// in-flight cache is not reused once a result has been resolved. Use
  /// a fresh [srcPath] to force a different cache entry.
  static Future<String> compressedPathFor(String srcPath) async {
    final cached = _inflight[srcPath];
    // Completer (not Future) is used so we can query isCompleted — Future
    // has no such getter.
    if (cached != null && !cached.isCompleted) return cached.future;

    final completer = Completer<String>();
    _inflight[srcPath] = completer;
    // onError is defense-in-depth: _doCompress never throws in practice.
    _doCompress(srcPath).then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  static Future<String> _doCompress(String srcPath) async {
    final srcFile = File(srcPath);
    if (!srcFile.existsSync()) return srcPath;
    final cachePath = cachePathFor(srcPath);

    // Reuse a previously-written cache file (cross-process reuse).
    if (File(cachePath).existsSync()) return cachePath;

    try {
      final raw = await srcFile.readAsBytes();
      final decoded = img.decodeImage(raw);
      if (decoded == null) {
        DebugService.instance.recordEvent(
          scope: 'compress',
          message: 'decode returned null, fallback to original',
          level: EventLevel.warn,
          data: {'src': srcPath},
        );
        return srcPath;
      }
      // Always re-encode to JPEG at longest edge 1600. For images whose
      // longest edge is already exactly 1600, copyResize is a no-op; for
      // smaller ones it's an upscale (VLM input is robust to upsampling);
      // for larger ones it's a downscale.
      final resized = decoded.width >= decoded.height
          ? img.copyResize(
              decoded,
              width: _kMaxEdge,
              maintainAspect: true,
              interpolation: img.Interpolation.linear,
            )
          : img.copyResize(
              decoded,
              height: _kMaxEdge,
              maintainAspect: true,
              interpolation: img.Interpolation.linear,
            );
      final jpg = img.encodeJpg(resized, quality: _kJpegQuality);
      await File(cachePath).parent.create(recursive: true);
      await File(cachePath).writeAsBytes(jpg);
      return cachePath;
    } catch (e) {
      DebugService.instance.recordEvent(
        scope: 'compress',
        message: 'compress failed, fallback to original',
        level: EventLevel.warn,
        data: {'src': srcPath, 'error': e.toString()},
      );
      return srcPath;
    }
  }
}
