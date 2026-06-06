# Little-Bug Round — Summary & Commit Index

> **Branch**: `fix/little-bug-fixes`
> **Window**: 27 commits from `5b47c8e` (audit) to `bed6382` (D-10) — see list below.
> **Spec / plan / verdict**:
> - `docs/superpowers/specs/2026-06-06-little-bug-fixes-design.md` (the spec)
> - `docs/superpowers/plans/2026-06-06-little-bug-fixes.md` (the TDD plan)
> - `docs/audits/2026-06-06-little-bug-verdict.md` (per-bug verdicts, 30 FIX / 3 REJECT / 2 DEFER)
>
> **Worktree note**: this branch is developed in a worktree at
> `/Users/concerto391/Documents/GitHub/gradenow-fast-littlebug/`. The Flutter
> project root *is* the worktree root (no `yas_local/` subdirectory in the
> worktree — `test/`, `lib/`, `pubspec.yaml` all live at the worktree root).
> The `gradenow-fast` *parent repo* contains a `yas_local/` subdirectory with
> its own `pubspec.yaml` and `test/`. After this branch merges, the parent
> repo's layout re-applies — see "Parent-repo sync" below.

## Scope at a glance

| Severity bucket | Items in scope | Items fixed | Items rejected / deferred |
|---|---|---|---|
| UX (U-*) | 17 | 16 | 1 (U-5 REJECT-AUDIT — c0 reviewer's verdict: not a bug) |
| Architecture-drift (A-*) | 3 | 2 (A-2, A-3) | 1 (A-4 already covered by sister plan c4d / C-1) |
| Documentation (D-*) | 10 | 8 (D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-10) | 1 (D-4 REJECT-AUDIT — debug export exists) |
| Test blindspots (subset of D-*) | — | 5 (D-6, D-7, D-8, D-9a, D-9b, D-9c) | — |

**Total**: 27 commits (1 audit + 26 fixes, of which 3 are D-9 sub-commits).

**Commits not made in this round**:

- U-15: covered by sister plan (`fix/selective-bug-fix`, `docs/superpowers/specs/2026-06-05-selective-bug-fix-design.md`).
- U-19: REJECT-AUDIT (c0) — `Image.file` placeholder is fine.
- A-1, A-4: covered by sister plan c4d / C-1.
- D-4: REJECT-AUDIT (c0) — debug export already exists.

## Commit index (oldest first)

| # | SHA | Subject | One-line |
|---|---|---|---|
| 0 | `5b47c8e` | docs(audit): log little-bug verdicts (30 fix, 3 audit-reject, 2 defer) | Records per-bug verdicts; sources cited. |
| 1 | `e2f9e6f` | fix(ux): enable system dark mode (U-1) | Adds `darkTheme` to `MaterialApp` so dark-mode users aren't blinded by white surfaces. |
| 2 | `ea41ab1` | fix(ux): debounce teacher score slider writes (U-2) | Switches `onChanged` → `onChangeEnd` on the score slider; adds `Debouncer` helper. |
| 3 | `4940199` | fix(ux): derive slider max from per-item checkpoint sum (U-3) | `maxPts` now reads `gradedItem.maxPoints`, with safe fallback. |
| 4 | `269d9dd` | fix(ux): correct "正在生成第 X/Y" off-by-one (U-4) | Progress text was `${done+1}/$total`; now correctly `$done/$total`. |
| 5 | `1ccbfc5` | fix(ux): snackbar + haptic when teacher confirms the last question (U-6) | After `_nextUnconfirmed()` returns null, show snackbar + `HapticFeedback.lightImpact`. |
| 6 | `e698322` | fix(ux): cap photo picker at 100 with snackbar (U-7) | Hard cap in `create_task_screen` + `capture_screen`; warn snackbar at the limit. |
| 7 | `6a21e65` | fix(ux): correct 2px spacer typo to 8px (U-8) | `SizedBox(height: 2)` → `SizedBox(height: 8)` between checkpoint rows. |
| 8 | `00d3fa0` | fix(ux): debounce regrade dialog "立即重批" button (U-9) | Guards `_rerunInProgress`; dialog open sets it true, both paths clear on close. |
| 9 | `47d7191` | fix(ux): pre-compute submissionsByTask once per build (U-10) | Replaces O(N×M) `firstWhereOrNull` loop with a `Map<taskId, lastSubmission>` built once. |
| 10 | `79010d9` | fix(ux): move retry banner into the question's own card (U-11) | Banner now scopes to a single question, not the whole review screen. |
| 11 | `c721287` | fix(ux): drop misleading "保留旧结果" button from regrade dialog (U-12) | Button was a snackbar hint, not an action; removed. |
| 12 | `ea29a5c` | fix(ux): add "返回首页" button to missing-task empty state (U-13) | Empty `Scaffold` for unknown taskId now offers a way out. |
| 13 | `a6620a4` | fix(ux): flag references whose question is missing from rubric (U-14) | "该题已从 rubric 中移除" banner instead of silent 0-point rows. |
| 14 | `46a3657` | fix(ux): add chevron + hover bg to tappable checkpoint rows (U-16) | Visual affordance: `Icons.chevron_right` + `Material` ink well. |
| 15 | `b93c247` | fix(ux): bump checkpoint row padding to meet iOS 44pt touch target (U-17) | Padding bumped to ≥ 44pt; satisfies iOS HIG. |
| 16 | `2496ac8` | fix(ux): SnackBar on chat send failure (U-18) | Failure surfaces in a snackbar, not just chat history. |
| 17 | `b80e7ae` | fix(ux): truncate URL + warn on ?key= in Dio error messages (U-20) | `ErrorFormatter` truncates long URLs and warns if `?key=` present. |
| 18 | `de7925a` | fix(arch): refineStrategy retries transport errors (A-2) | Wraps `refineStrategy` HTTP in try/catch; honors `_shouldRetry` for transport errors. |
| 19 | `9a78e44` | fix(arch): balanced-bracket scanner for JSON fallback (A-3) | Replaces `indexOf/lastIndexOf` JSON extraction fallback with a balanced-bracket scanner. |
| 20 | `6926ff4` | docs: fix log filename qwen_*.log → yas_*.log (D-1) | `CLAUDE.md` + `README.md` say `yas_*.log` to match `lib/main.dart:32`. |
| 21 | `cff904c` | test: tighten maxAttempt >= 2 → equals 3 (D-6) | Asserts the retry policy is *exactly* 3 attempts, not ≥ 2. |
| 22 | `2de2431` | test: rename grading_test.dart → checkpoint_math_test.dart (D-7) | Filename now matches what it actually tests. |
| 23 | `319d6ab` | test: assert LaTeX actually rendered, not just mounted (D-8) | RichContent test now verifies the LaTeX glyphs are visible, not just that the widget is mounted. |
| 24 | `436edb2` | test: add smoke test for identify_screen (D-9a) | New `test/identify_screen_test.dart` covers mount + key widgets. |
| 25 | `9da9ef1` | test: add smoke test for create_task_screen (D-9b) | New `test/create_task_screen_test.dart`. |
| 26 | `b735383` | test: add smoke test for home_screen (D-9c) | New `test/home_screen_test.dart`. |
| 27 | `bed6382` | fix(debug): clear() resets _stats (D-10) | `DebugService.clear()` was leaving per-sink stats; now resets them too. |

> The expected c-final sync (this commit + the parent-repo sync) is
> documented in "Parent-repo sync" below; the in-worktree artifacts of c-final
> live in this file.

## Test / analyze results

Measured at the tip of the round (`bed6382`, before the c-final commit):

- `flutter analyze` → **No issues found** (0 errors, 0 warnings, 0 info).
- `flutter test` → **356 passed, 1 skipped, 1 failed**.
  - Skip: `atomic_io_test.dart` "readJsonOrQuarantine when the rename itself
    fails" — annotated `Skip: rename-failure path is exercised by integration
    tests`. Pre-existing.
  - Failure: `debug_sink_test.dart` "RollingFileSink rotates when file
    exceeds maxFileBytes" — **pre-existing on `origin/main`**, not introduced
    by this round. Verified by checking out the test file at `origin/main`:
    it fails identically. Out of scope for this round.

Baseline at `origin/main` (the sister plan's tip): 348 passing, 1 skipped,
1 failed (same). The little-bug round adds 8 net new passing tests
(`checkpoint_math_test`, `create_task_screen_test`, `identify_screen_test`,
`home_screen_test`, `error_formatter_test` U-20, `photo_cap_test` U-7,
`paper_detail_maxpoints_test` U-3, `paper_detail_slider_test` U-2,
`task_detail_regrade_dialog_test` U-9, `task_detail_regrade_debounce_test`
U-9, `strategy_provider_missing_rubric_test` U-14,
`strategy_review_confirm_test` U-6, `chat_sheet_error_test` U-18, etc.).

## Files touched

72 files changed, 6107 insertions(+), 4614 deletions(-).

Highlights:

- `lib/app.dart` — darkTheme (U-1).
- `lib/utils/debouncer.dart` — new shared debouncer helper (U-2, U-9, U-18).
- `lib/services/json_extractor.dart` — balanced-bracket scanner (A-3).
- `lib/services/qwen_service.dart` — refineStrategy retry (A-2).
- `lib/services/error_formatter.dart` — URL truncation + key warning (U-20).
- `lib/services/debug/debug_service.dart` — `clear()` resets `_stats` (D-10).
- `lib/screens/home_screen.dart` — `subsByTask` once-per-build (U-10).
- `lib/screens/paper_detail_screen.dart` — slider max from checkpoints, debounced writes (U-2, U-3).
- `lib/screens/strategy_review_screen.dart` — last-confirm snackbar/haptic, retry banner scoping (U-4, U-6, U-11).
- `lib/screens/strategy_review/question_page.dart` — 8px spacer, chevron, 44pt row (U-8, U-16, U-17).
- `lib/screens/strategy_review/chat_sheet.dart` — send-failure snackbar (U-18).
- `lib/screens/capture_screen.dart` + `lib/screens/create_task_screen.dart` — 100-photo cap (U-7).
- `lib/screens/task_detail_screen.dart` — debounced regrade button, remove misleading button, return-home on empty (U-9, U-12, U-13).
- `lib/providers/strategy_provider.dart` — missing-rubric banner (U-14).
- `yas_local/README.md` — `qwen_*.log` → `yas_*.log` (D-1).
- New test files: `test/checkpoint_math_test.dart`, `test/create_task_screen_test.dart`, `test/identify_screen_test.dart`, `test/home_screen_test.dart` (D-7, D-9a/b/c).
- Removed/deleted: `test/grading_test.dart` (D-7), `test/image_compressor_test.dart` (c4d sister, content moved to `image_compressor_io_test.dart`).

## Parent-repo sync (manual step for whoever merges this branch)

**Why this is needed**: the worktree at `gradenow-fast-littlebug/` does **not**
contain its own `CLAUDE.md`. The repository's `CLAUDE.md` lives in the parent
repo at `gradenow-fast/CLAUDE.md`, and that file is what the Claude Code
harness reads on the merged `main` branch. This worktree round fixed 5 doc
bugs (D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-10), and **all 5 still need to
be applied to the parent `gradenow-fast/CLAUDE.md`** at the same time as
this branch is merged. (D-1's `README.md` half is already in the worktree's
`yas_local/README.md`, which becomes the post-merge README once the merge
resolves `yas_local/README.md` from the parent — the worktree's
`README.md` at the root is the doc, not the user-facing one.)

What to change in `gradenow-fast/CLAUDE.md` after this branch merges:

| ID | Line (current `gradenow-fast/CLAUDE.md`) | Change |
|---|---|---|
| D-1 | `:120` | `qwen_YYYY-MM-DD.log` → `yas_YYYY-MM-DD.log` (filename only; the `QwenLogger` heading stays since the class is still called `QwenLogger`). |
| D-1 | `:120` | `qwen_YYYY-MM-DD.1.log` → `yas_YYYY-MM-DD.1.log`. |
| D-2 | `:80` (mutex claim) | Change "TaskStore writes are serialized via a mutex (see `TaskNotifier._persistChain` in `task_provider.dart:42-58`)" wording — the mutex lives in `TaskNotifier._persistChain`, not `TaskStore`. (Already accurate on the current parent; verify the text didn't drift.) |
| D-3 | `:142` (image preprocessing) | Change "longest edge ≤ 1600px" → "longest edge forced to 1600px" — smaller images are upscaled, larger downscaled. |
| (D-5) | (parent `docs/2026-05-31-yas-local-mvp.md`) | Add a "SUPERSEDED" banner at the top so future readers know `grading-redesign.md` supersedes it. The worktree's `docs/` re-adds this file via the merged branch. |
| (UX) | (new section to add) | "**UX fixes (2026-06-06 round)**" — list of all 16 U-* + 2 A-* + 4 test commits from the table above. (See "Suggested parent CLAUDE.md additions" below.) |
| (UX) | (new one-liner) | "**Dark mode**: `darkTheme` is enabled in `lib/app.dart`; a visual sweep of all screens in dark mode is a follow-up (R6 in the spec)." |

### Suggested parent CLAUDE.md additions

In "**Key patterns**" section, add:

```
- **UX fixes (2026-06-06 round)** — 27 small commits on `fix/little-bug-fixes`:
  - U-1 darkTheme (e2f9e6f), U-2 slider debounce (ea41ab1), U-3 maxPts from
    checkpoints (4940199), U-4 progress text off-by-one (269d9dd), U-6 last-
    confirm snackbar/haptic (1ccbfc5), U-7 photo cap 100 (e698322), U-8 8px
    spacer (6a21e65), U-9 regrade debounce (00d3fa0), U-10 subsByTask once
    (47d7191), U-11 retry banner per question (79010d9), U-12 drop misleading
    button (c721287), U-13 return-home button (ea29a5c), U-14 missing-rubric
    banner (a6620a4), U-16 chevron + hover (46a3657), U-17 44pt touch target
    (b93c247), U-18 chat send snackbar (2496ac8), U-20 URL truncation (b80e7ae).
  - A-2 refineStrategy retry (de7925a), A-3 balanced-bracket JSON scanner
    (9a78e44).
  - D-1/2/3/5/6/7/8/10 doc/test cleanups (6926ff4..bed6382).
  - Full table: docs/superpowers/specs/2026-06-06-little-bug-round-summary.md
    in the merged branch.
```

In "**Architecture**" section, add after the routing paragraph:

```
- **Dark mode**: `darkTheme` is enabled in `lib/app.dart` (commit `e2f9e6f`,
  U-1). A visual sweep of all screens in dark mode is a follow-up task (R6 in
  `docs/superpowers/specs/2026-06-06-little-bug-fixes-design.md`).
```

## Cross-references

- Design spec: `docs/superpowers/specs/2026-06-06-little-bug-fixes-design.md`
- TDD plan: `docs/superpowers/plans/2026-06-06-little-bug-fixes.md`
- Audit verdict: `docs/audits/2026-06-06-little-bug-verdict.md`
- c0 audit (predecessor): `docs/audits/2026-06-05-bug-report-review.md` (lives
  on the parent repo at the time of c0; the worktree doesn't carry it because
  the round was scoped to little-bug items only)
- Bug list: `docs/bbbbbiiiigBugs.md` (parent repo only — not committed to
  the worktree)
