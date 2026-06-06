# Bug Report Review — `docs/bbbbbiiiigBugs.md`

> **Audit date:** 2026-06-05
> **Method:** Code-read pass; every claim verified against file:line evidence.
> **Test baseline:** `flutter test` 326/326 passing, `flutter analyze` 1 info.
> **Verdict counts:** 35 ✅ CONFIRMED · 14 ⚠️ PARTIALLY CONFIRMED · 6 ❌ WRONG

This audit exists so that the 15 CONFIRMED 0+1-level bug IDs fixed in commits c1–c11 are traceable, and so that the 6 WRONG and 14 PARTIALLY CONFIRMED claims are not silently re-litigated in the future.

---

## A. 6 WRONG claims (do not fix)

| Claim ID | Verdict | Why wrong |
|---|---|---|
| C-6a | WRONG | `json_extractor.dart:224` uses `.*?` (non-greedy), not greedy. The real path uses `_splitReasoning` (line 210), which is even safer. The "3× cost" claim is not supported by the code. |
| C-8 | WRONG | `rolling_file_sink.dart:59-63` flushes the previous write at the top of each call (under `_writeLock`). The "lose a batch" claim does not match the implementation. |
| S-3 | WRONG | `qwen_service.dart:484-486` raises `TypeError` (Dart core) on null body, not `NoSuchMethodError`. Line 500-506 matches `e is TypeError`, so the Debug screen **does** record the parse error. |
| S-11 | WRONG | The symbol `graderuleProvider` does not exist in `lib/` or `test/`. grep returns 0 results. The claim is unsubstantiated. |
| D-4 | PARTIALLY WRONG | `lib/services/debug/debug_export.dart` **does** exist; `test/debug_export_test.dart` has 46 lines. The claim that the spec was "completely not implemented" is overstated — paths/names differ, but export capability is present. |
| U-19 | WRONG | `Image.file` on a missing file shows a broken-image placeholder, not a crash. Flutter's image widget handles missing files gracefully. |

## B. 14 PARTIALLY CONFIRMED claims (deferred to future round)

| Claim ID | Verdict | Real severity vs claim |
|---|---|---|
| C-6b | Partial | Real risk (Chinese `{` corrupts brace-fallback), but 2 attempts not 3; code-fence first, brace-fallback second. |
| S-1 | Partial | Real, but trigger is narrow (user pastes URL with `?key=`). Easy fix. |
| S-2 | Partial | Real, but `refineStrategy` is intentionally not under `_retryingRequest` (CLAUDE.md "Comments" — multi-turn). Fix would touch VLM core; deferred. |
| S-6 | Partial | Real (type erasure on `_retryWithFeedback`), but the call site is small; a one-line explicit type fixes it. |
| U-5 | Partial | Real, but the consumer filters by `refiningQuestion`, so other questions are not actually blocked. |
| U-10 | Partial | Real, but worst case is ~600 comparisons/build, not 3000/sec. |
| U-11 | Partial | Real UX confusion, but no data loss. |
| U-12 | Partial | Real (3 buttons look like actions but "保留旧结果" is just a snackbar hint), but text-only. |
| U-14 | Partial | Real, but only triggers if teacher edits rubric while refs are loaded. |
| U-18 | Partial | Real (chat error vs thinking looks identical), but no data loss. |
| U-20 | Partial | Real (API key in URL leaks), but trigger requires user to paste URL with `?key=`. |
| D-1 | Partial | Real, but only `qwen_*.log` filename is wrong; `main.dart:32` writes `yas_*.log`. Documentation mismatch, not a code bug. |
| D-2 | Partial | Real, but the mutex IS in `_persistChain` (documented in `task_store.dart:56-62`); CLAUDE.md is just imprecise. |
| D-3 | Partial | Real, but only the "≤" symbol is wrong — code is "= 1600" (forces resize). Small-image upscaling. |

## C. 35 CONFIRMED claims

| Severity | IDs | Fix in this round? |
|---|---|---|
| 0 (data loss) | C-1, C-2, C-3, C-4, C-5, C-9 | **Yes** — Tasks 2, 3, 4, 5, 6, 7 |
| 1 (state) | S-4, S-5, S-6, S-7, S-8, S-9, S-10, S-12, U-15 | **Yes** — Tasks 8, 9, 10, 11, 12, 13, 14, 15, 16 |
| 2 (UX) | U-1, U-2, U-3, U-4, U-6, U-7, U-8, U-9, U-11, U-13, U-15, U-16, U-17, U-18, U-20 | **Partial** — only U-15 in this round |
| 2 (doc) | D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-9, D-10 | **Yes (D-1, D-2, D-3 in CLAUDE.md sync; D-6/D-10 tests fixed)** |
| 3 (arch) | A-1, A-2, A-3, A-4 | **A-1 root-cause named in c4d; A-4 same as C-1; A-2/A-3 deferred** |
