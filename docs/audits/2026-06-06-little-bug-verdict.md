# Little-Bug Verdict — `docs/bbbbbiiiigBugs.md` UX/Doc/Arch items

> **Audit date:** 2026-06-06
> **Method:** Re-read of every U/D/A claim in `bbbbbiiiigBugs.md` against `origin/main` source, cross-referenced with `docs/audits/2026-06-05-bug-report-review.md`.
> **Source bug report:** `docs/bbbbbiiiigBugs.md`
> **Sister plan:** `docs/superpowers/specs/2026-06-05-selective-bug-fix-design.md` (L0/L1 fixes, branch `fix/selective-bug-fix`).

This audit classifies every remaining (U/D/A) bug claim into one of four buckets: **FIX** (patched in this round), **REJECT-AUDIT** (c0 audit already documented as wrong/partial), **DEFER** (real but architectural rewrite; out of scope), **N/A** (sister plan covers it).

---

## A. Will FIX in this round (30 commits)

| ID | Severity | One-line fix |
|---|---|---|
| U-1 | UX | Add `darkTheme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(..., brightness: dark))` to `lib/app.dart:36-41` |
| U-2 | UX | Slider `onChanged` → local state; `onChangeEnd` → debounced save (200ms) via new `lib/utils/debouncer.dart` |
| U-3 | UX | `rubricByNum[item.questionNumber]?.maxPoints ?? 20` → `item.maxPoints` (per-question) |
| U-4 | UX | `'正在生成第 ${done + 1}/$total'` → `'正在生成第 $done/$total'` |
| U-6 | UX | After `_nextUnconfirmed()` returns null on last confirm, show `SnackBar` + `HapticFeedback.heavyImpact()` |
| U-7 | UX | `kMaxSubmissions = 100` cap; show snackbar when reached |
| U-8 | UX | `SizedBox(height: 2)` → `SizedBox(height: 8)` |
| U-9 | UX | Regrade dialog button reads `_rerunInProgress`; both paths clear in `finally` |
| U-10 | UX | Hoist `submissionsFor` call out of the `Builder`; pass slice down |
| U-11 | UX | Move retry banner from screen-level to per-question card |
| U-12 | UX | Remove "保留旧结果" button (was a snackbar hint, not an action) |
| U-13 | UX | Add "返回首页" `FilledButton` to the empty-task Scaffold |
| U-14 | UX | When rubric missing, show banner "该题已从 rubric 中移除"; do not render 0-point row |
| U-16 | UX | Add leading `Icons.chevron_right` to each checkpoint row + hover background |
| U-17 | UX | Increase row padding so height ≥ 44pt (iOS HIG) |
| U-18 | UX | Chat send failure → `SnackBar` (not only in history) |
| U-20 | UX | Truncate URL in `ErrorFormatter`; warn if `?key=` substring present |
| A-2 | Arch | `refineStrategy`: try/catch on HTTP, classify to `QwenError`, honor `shouldRetry` |
| A-3 | Arch | Replace `indexOf`/`lastIndexOf` fallback with balanced-bracket scanner |
| D-1 | Doc | `qwen_*.log` → `yas_*.log` in `CLAUDE.md:120` + `README.md:22` |
| D-2 | Doc | Mutex claim: "TaskStore" → "TaskNotifier._persistChain" |
| D-3 | Doc | "longest edge ≤ 1600px" → "longest edge forced to 1600px" |
| D-5 | Doc | Add `> **SUPERSEDED**` banner + 10-route list to MVP plan |
| D-6 | Test | `>= 2` → `== 3` in `test/job_queue_retry_test.dart:204-211` |
| D-7 | Test | Rename `test/grading_test.dart` → `test/checkpoint_math_test.dart` |
| D-8 | Test | Add LaTeX-actually-rendered assertion to `test/rich_content_test.dart` |
| D-9a | Test | New `test/identify_screen_test.dart` |
| D-9b | Test | New `test/create_task_screen_test.dart` |
| D-9c | Test | New `test/home_screen_test.dart` |
| D-10 | Test | `DebugService.clear()` resets `_stats` |

## B. REJECT-AUDIT (c0 audit already documented; no fix)

| ID | c0 verdict | Why |
|---|---|---|
| U-5 | PARTIAL | `strategy_review_screen.dart:312-314` already filters by `refiningQuestion`. Per-question lock is correct. |
| U-19 | WRONG | `Image.file` on missing file shows a broken-image placeholder. No crash. |
| D-4 | PARTIALLY WRONG | `lib/services/debug/debug_export.dart` exists; `test/debug_export_test.dart` has 46 lines. Spec/impl drift is real but not "completely unimplemented". |

## C. DEFER (architectural rewrite, not this round)

| ID | Why deferred | Future round |
|---|---|---|
| Full unification of `_retryingRequest` and `refineStrategy` (related to A-2) | Requires body-builder abstraction; touches all 4 VLM call sites | `2026-06-XX-retry-unification` |
| Streaming JSON parser (A-3 follow-up) | Incremental scanner is enough for current VLM output sizes | `2026-06-XX-streaming-json` |

## D. N/A (sister plan covers)

| ID | Sister commit |
|---|---|
| C-1..C-9 | various |
| S-1..S-12, U-15 | various |
| A-1 | c4d |
| A-4 (= C-1) | c1 |
