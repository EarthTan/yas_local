import 'dart:io';

import 'package:path/path.dart' as p;

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
  /// only triggers one decode. Stores `Future<String>` (not `String`) so
  /// in-flight work is also deduped.
  static final Map<String, Future<String>> _inflight = {};

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
  static Future<String> compressedPathFor(String srcPath) async {
    if (!File(srcPath).existsSync()) return srcPath;
    // Decode/resize/encode is added in Task 3 of this plan. The Task 2
    // body intentionally returns srcPath so the existing-fail / naming
    // tests pass without depending on the image package.
    return srcPath;
  }
}
