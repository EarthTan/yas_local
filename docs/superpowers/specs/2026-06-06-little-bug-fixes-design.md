# Little Bug Fixes — UX, Documentation & Architecture Drift

> **Source audit**: `docs/bbbbbiiiigBugs.md` (5 subagent code-read pass, 2026-06-05).
> **Sister plan**: `docs/superpowers/specs/2026-06-05-selective-bug-fix-design.md` already covers 0+1-level (C-/S-/U-15) bugs on branch `fix/selective-bug-fix`. This spec covers the **remaining** UX (U-*), documentation (D-*), and architecture-drift (A-*) items that the sister spec defers as "out of scope".
> **Strategy**: localized patches per bug; one commit per bug ID. No architectural rewrites — the architecture-drift items (A-2, A-3, A-4) are small, contained fixes.
> **Discipline**: TDD (red-green-refactor) where a unit test is the natural fit; text-only edits for documentation bugs (D-1, D-2, D-3, D-5). `flutter test` and `flutter analyze` must stay clean.
> **Traceability**: every commit message body references `bbbbbiiiigBugs.md#<id>` and the c0 audit verdict where applicable.

---

## 0. Scope Summary

| Severity | Total | Will fix here | Already covered / rejected | Notes |
|---|---|---|---|---|
| 0 (data loss) | 9 | 0 | C-1..C-9 covered by sister plan | |
| 1 (state) | 24 | 0 | S-1..S-12, U-15 covered by sister plan | |
| 2 (UX) | 25+ | 17 | U-5 (rejected), U-15 (sister), U-19 (rejected) | see §1 |
| 2 (doc) | 7+ | 5 | D-4 (rejected as overstated) | D-1..D-3, D-5, D-6, D-7, D-8, D-9, D-10 |
| 3 (test blindspot) | — | (subset of D-7, D-8, D-9) | | see §1 |
| 3 (arch) | 4 | 3 | A-1 (sister c4d) | A-2, A-3, A-4 |

**Total commits in this plan**: 17 (UX) + 5 (doc) + 1 (test) + 3 (arch) = **26 commits** + 1 meta c0 + 1 docs-sync c-final = **28 commits**.

(The D-9 row counts as 3 sub-commits: identify / create_task / home. See §3.4.)

---

## 1. Bug-by-bug Verdict (cross-checked against c0 audit + origin/main)

The c0 audit at `docs/audits/2026-06-05-bug-report-review.md` already issued verdicts on the 14 PARTIALLY CONFIRMED claims. I re-verified every "little bug" claim against `origin/main` source and the audit, then made one of four calls: **FIX**, **REJECT (audit)**, **REJECT (overstated)**, or **DEFER (small re-write beyond this round)**.

### 1.1 UX bugs (U-*)

| ID | Decision | Source line (origin/main) | Reason / one-line fix |
|---|---|---|---|
| U-1 | **FIX** | `lib/app.dart:36-41` | Add `darkTheme` so teachers on dark-mode phones aren't blinded by white. |
| U-2 | **FIX** | `lib/screens/paper_detail_screen.dart:99-115` | Slider: debounce `onChanged` to `onChangeEnd`; debounced save (200ms). |
| U-3 | **FIX** | `lib/screens/paper_detail_screen.dart:29` | `maxPts ?? 20` → use `gradedItem.maxPoints` from item, with safe fallback. |
| U-4 | **FIX** | `lib/screens/strategy_review_screen.dart:147` | `'正在生成第 ${done + 1}/$total'` → `'正在生成第 $done/$total'`. |
| U-5 | **REJECT (audit)** | `lib/screens/strategy_review_screen.dart:312-314` | Call site already filters by `refiningQuestion`. Per c0 audit: PARTIALLY CONFIRMED, not a bug. |
| U-6 | **FIX** | `lib/screens/strategy_review_screen.dart:316-323` | After `_nextUnconfirmed()` returns null (last confirmed), show snackbar + haptic. |
| U-7 | **FIX** | `lib/screens/capture_screen.dart:42-46` + `lib/screens/create_task_screen.dart:51-55, 85-90` | Cap at 100; show warning snackbar when reached. |
| U-8 | **FIX** | `lib/screens/strategy_review/question_page.dart:127-145` | `SizedBox(height: 2)` → `SizedBox(height: 8)`. |
| U-9 | **FIX** | `lib/screens/task_detail_screen.dart:462-497` | Same `_rerunInProgress` guard as the button; dialog open sets state true, both paths clear. |
| U-10 | **FIX** | `lib/screens/home_screen.dart:172-251` | Pre-compute `subsByTask` map once per build (or cache on state). |
| U-11 | **FIX** | `lib/screens/strategy_review_screen.dart:217-227` | Move banner inside the per-question `Card`, not screen-level. |
| U-12 | **FIX** | `lib/screens/task_detail_screen.dart:425-460` | Remove "保留旧结果" button (it was a snackbar hint, not an action). |
| U-13 | **FIX** | `lib/screens/task_detail_screen.dart:73` | Add "返回首页" button to the empty Scaffold. |
| U-14 | **FIX** | `lib/providers/strategy_provider.dart:158-165, 80-87` | When rubric missing, show a "该题已从 rubric 中移除" banner, not 0-point rows. |
| U-15 | covered by sister | — | — |
| U-16 | **FIX** | `lib/screens/strategy_review/question_page.dart:124-148` | Add a leading chevron + background on hover. |
| U-17 | **FIX** | `lib/screens/strategy_review/question_page.dart` (file-wide) | Increase checkpoint row padding so height ≥ 44pt. |
| U-18 | **FIX** | `lib/screens/strategy_review/chat_sheet.dart:115-124` | On send failure, surface a snackbar (not only in history). |
| U-19 | **REJECT (audit)** | `lib/screens/paper_detail_screen.dart:25-26` | `Image.file` on missing file shows broken-image placeholder. Per c0 audit: WRONG. |
| U-20 | **FIX** | `lib/services/error_formatter.dart:16-38` | Truncate URL in error display; warn if `?key=` present. |

### 1.2 Documentation bugs (D-*)

| ID | Decision | Source line (origin/main) | Reason / one-line fix |
|---|---|---|---|
| D-1 | **FIX** | `CLAUDE.md:120` + `README.md:22` | Replace `qwen_*.log` → `yas_*.log` to match `lib/main.dart:32`. |
| D-2 | **FIX** | `CLAUDE.md:80` | Move mutex claim from "TaskStore" → "TaskNotifier._persistChain". |
| D-3 | **FIX** | `CLAUDE.md:142` | Change "longest edge ≤ 1600px" → "longest edge forced to 1600px". |
| D-4 | **REJECT (audit)** | — | Per c0 audit: PARTIALLY WRONG (debug export DOES exist). No fix. |
| D-5 | **FIX** | `docs/2026-05-31-yas-local-mvp.md:1037-1047` | Add "SUPERSEDED" banner + correct 10-route list. |
| D-6 | **FIX** | `test/job_queue_retry_test.dart:204-211` | `>= 2` → `== 3`. |
| D-7 | **FIX** | `test/grading_test.dart` | Rename to `test/checkpoint_math_test.dart` (or delete and move cases to `checkpoint_test.dart`). |
| D-8 | **FIX** | `test/rich_content_test.dart:55-124` | Add a "LaTeX actually rendered" assertion (look for `RichText` with `RichTextSpan` containing `MathSpec.tex` children, or simply assert that the LaTeX raw text is not visible). |
| D-9 | **FIX** | `test/identify_screen_test.dart` / `test/create_task_screen_test.dart` / `test/home_screen_test.dart` | Create 3 test files. (3 separate commits per user's preference.) |
| D-10 | **FIX** | `lib/services/debug/debug_service.dart:283-286` | `clear()` resets `_stats` too. |

### 1.3 Architecture-drift bugs (A-*)

| ID | Decision | Source line (origin/main) | Reason / one-line fix |
|---|---|---|---|
| A-1 | covered by sister c4d | — | — |
| A-2 | **FIX (small)** | `lib/services/qwen_service.dart:262-305` | Wrap `refineStrategy` HTTP call in try/catch; classify DioException → QwenError; honor `_shouldRetry` for transport errors. Architectural rewrite deferred to a future round; here we add **at least one** try/catch + retry for transport errors. |
| A-3 | **FIX (small)** | `lib/services/json_extractor.dart:238-247, 249-258` | Replace the indexOf/lastIndexOf fallback with a balanced-bracket scanner that tries each candidate. |
| A-4 | covered by sister (same as C-1) | — | `setSubmissions` renamed in c1. |

> **Why "small" for A-2 and A-3?** The user asked for localized patches, not architectural rewrites. Both fixes are < 30 lines and target one bug each. A full unification of retry paths (A-2) or a streaming JSON parser (A-3) is a larger project for another day.

---

## 2. Architecture Changes

### 2.1 U-2 / U-9 / U-18 — Debounce pattern

A small **shared debouncer** is needed in 3 places (teacher score slider, re-grade dialog button, chat send). Rather than 3 ad-hoc Timers, the plan adds a tiny helper:

```dart
// lib/utils/debouncer.dart
class Debouncer {
  final Duration delay;
  Timer? _t;
  Debouncer(this.delay);
  void call(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }
  void flush() => _t?.cancel();  // caller fires action immediately
  void dispose() => _t?.cancel();
}
```

- **U-2**: slider `onChanged` updates a local `double _dragValue` (rebuild widget only), `onChangeEnd` calls `notifier.updateSubmission(...)` (single disk write). The drag value is lost on rebuild — that's fine, parent state still has the final value.
- **U-9**: the regrade dialog open sets `_rerunInProgress = true` in the parent; the dialog's "立即重批" button reads parent's flag and disables itself. Either path (`_rerunFailedGrading` / `cancel` / dialog dismiss) clears it in `finally`.
- **U-18**: chat send catches `StateError` and shows `ScaffoldMessenger.showSnackBar(SnackBar(content: Text('发送失败，请重试')))` — local concern, no debouncer.

### 2.2 U-10 — Home O(N×M) fix

`home_screen.dart` currently does:
```dart
for (final t in state.tasks.reversed) {
  Builder(builder: (context) {
    final subs = notifier.submissionsFor(t.id);  // O(M)
    final subDone = subs.where(...).length;       // O(M)
    final subFailed = subs.where(...).length;     // O(M)
  });
}
```

For N=10, M=30: 10×(30+30+30) = 900 comparisons per build.

**Fix** (committed in c-ux10): in the parent `Consumer`, build a `Map<String, List<Submission>>` once with a single pass, then pass each task's slice down. Builder does only `where().length` on its own slice (2×30 = 60 comparisons). Net: ~660 saved per build, and one per-build pass vs N.

This is **not** premature optimization — the build fires on every `JobQueue` progress update (~1 Hz), and the fix is one closure extraction. No new abstractions.

### 2.3 A-2 — `refineStrategy` retry for transport errors

```dart
// lib/services/qwen_service.dart
Future<StrategyRefinement> refineStrategy({...}) async {
  QwenError? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final resp = await _dio.post('/chat/completions', data: body);
      // ...existing JSON parse path...
      return result;
    } on DioException catch (e) {
      lastError = _toQwenError(e);
      if (!lastError.shouldRetry) rethrow;
      if (attempt < 1) await Future.delayed(_backoffMs(attempt));
    } on JsonParseException catch (e) {
      lastError = QwenError.parse(e.toString());
      if (attempt < 1) await Future.delayed(_backoffMs(attempt));
    }
  }
  throw lastError ?? QwenError.unknown('refineStrategy failed');
}
```

This makes the existing 2-attempt loop **actually catch transport errors**, which it didn't before. No new behavior, just fixes the bug. The future "unify with `_retryingRequest`" work is a separate architectural refactor (out of scope).

### 2.4 A-3 — Balanced-bracket JSON scanner

```dart
// lib/services/json_extractor.dart
List<int>? _scanBalancedBrackets(String text, {required bool isObject}) {
  // Walk char-by-char; for each '{' (or '['), find the matching '}' (or ']')
  // respecting strings and escapes. Return the candidate substring.
  // Caller tries each candidate in order until jsonDecode succeeds.
}
```

Replace the current `indexOf('{')` / `lastIndexOf('}')` slice with a function that yields **all** balanced-bracket candidates, then tries them in order. If the first one is corrupt (e.g. Chinese `{` corrupted the slice), the second one succeeds.

**Test**: A fixture where the LLM output is `"思考: 看到 { 我...\n{\n\"a\": 1\n}\n尾巴 }"` should now return `{"a": 1}` — the second balanced candidate, not the first corrupted one.

### 2.5 U-7 — Photo cap

Add `static const int kMaxSubmissions = 100;` to `lib/screens/capture_screen.dart`. Add the same constant to `lib/screens/create_task_screen.dart` (for question papers). Show a snackbar `"已达 100 张上限"` when cap is reached.

### 2.6 D-9 — Three new screen tests

Each test file is a smoke test:
- **identify_screen_test.dart**: pump the screen with a mock `IdentificationNotifier`; verify each question appears; verify a single edit propagates; verify back button.
- **create_task_screen_test.dart**: pump; verify field validation; verify submit.
- **home_screen_test.dart**: pump with 2 tasks; verify cards render; verify status text is correct.

These are widget tests (need `TestWidgetsFlutterBinding`); use `ProviderContainer` + `UncontrolledProviderScope` per the pattern in `test/capture_screen_test.dart`.

### 2.7 D-1 / D-2 / D-3 / D-5 — Doc text edits

| File | Change |
|---|---|
| `CLAUDE.md` line 120 | `qwen_YYYY-MM-DD.log` → `yas_YYYY-MM-DD.log` |
| `CLAUDE.md` line 80 | Mutex claim → "TaskNotifier._persistChain in `task_provider.dart:42-58`" |
| `CLAUDE.md` line 142 | `≤ 1600px` → `forced to 1600px` (longest edge, no upper bound on upscaling) |
| `README.md` line 22 | `qwen_*.log` → `yas_*.log` |
| `docs/2026-05-31-yas-local-mvp.md` line 1 | Add `> **SUPERSEDED — see `docs/superpowers/specs/2026-06-05-…` and `…/2026-06-06-little-bug-fixes-design.md`**` at the top; rewrite the routes section (7 → 10) |

### 2.8 U-1 — darkTheme

```dart
// lib/app.dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
  useMaterial3: true,
),
darkTheme: ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
),
themeMode: ThemeMode.system,
```

That's the entire change. The app's screens already use `Theme.of(context)` colors and the dark variant will Just Work for the M3 widgets. The `feedback_white_bg_black_text.md` memory still applies: any custom `Colors.white` background in the app needs an explicit `Color(0xFF000000)` text color override. This is **not** in scope of this plan (we just enable the theme; visual sweep is a separate UX task).

---

## 3. Commit Schedule

### 3.1 Ordering principle

- **c0** first: meta audit log
- UX fixes sorted by **independence** (no file overlap) so commits can land in any order
- Doc fixes are pure-text; cluster them at the end so a single re-read catches all doc drift
- Arch fixes (A-2, A-3) are independent of UX/Doc; do them between UX and Doc
- **c-final**: single docs-sync commit + acceptance checklist

### 3.2 Commit map

| # | Commit | Bug | Files | Tests | Risk |
|---|---|---|---|---|---|
| 0 | c0 | (meta) | `docs/audits/2026-06-06-little-bug-verdict.md` | none | none |
| 1 | c-ux1 | U-1 | `lib/app.dart` | none (visual) | low |
| 2 | c-ux2 | U-2 | `lib/screens/paper_detail_screen.dart`, `lib/utils/debouncer.dart` | `test/debouncer_test.dart`, `test/paper_detail_slider_test.dart` | low |
| 3 | c-ux3 | U-3 | `lib/screens/paper_detail_screen.dart` | `test/paper_detail_maxpoints_test.dart` | low |
| 4 | c-ux4 | U-4 | `lib/screens/strategy_review_screen.dart` | (text-only) | none |
| 5 | c-ux6 | U-6 | `lib/screens/strategy_review_screen.dart` | `test/strategy_review_confirm_test.dart` | low |
| 6 | c-ux7 | U-7 | `lib/screens/capture_screen.dart`, `lib/screens/create_task_screen.dart` | `test/photo_cap_test.dart` | low |
| 7 | c-ux8 | U-8 | `lib/screens/strategy_review/question_page.dart` | (visual) | none |
| 8 | c-ux9 | U-9 | `lib/screens/task_detail_screen.dart` | `test/task_detail_regrade_debounce_test.dart` | low |
| 9 | c-ux10 | U-10 | `lib/screens/home_screen.dart` | `test/home_perf_test.dart` (asserts one pass) | low |
| 10 | c-ux11 | U-11 | `lib/screens/strategy_review_screen.dart` | (visual) | low |
| 11 | c-ux12 | U-12 | `lib/screens/task_detail_screen.dart` | `test/task_detail_regrade_dialog_test.dart` | low |
| 12 | c-ux13 | U-13 | `lib/screens/task_detail_screen.dart` | (visual) | low |
| 13 | c-ux14 | U-14 | `lib/providers/strategy_provider.dart` | `test/strategy_provider_missing_rubric_test.dart` | low |
| 14 | c-ux16 | U-16 | `lib/screens/strategy_review/question_page.dart` | (visual) | none |
| 15 | c-ux17 | U-17 | `lib/screens/strategy_review/question_page.dart` | (visual; no new test) | none |
| 16 | c-ux18 | U-18 | `lib/screens/strategy_review/chat_sheet.dart` | `test/chat_sheet_error_test.dart` | low |
| 17 | c-ux20 | U-20 | `lib/services/error_formatter.dart` | `test/error_formatter_test.dart` (new) | low |
| 18 | c-arch2 | A-2 | `lib/services/qwen_service.dart` | `test/qwen_service_retry_test.dart` (additions) | med |
| 19 | c-arch3 | A-3 | `lib/services/json_extractor.dart` | `test/json_extractor_test.dart` (additions) | med |
| 20 | c-doc1 | D-1 | `CLAUDE.md`, `README.md` | none | none |
| 21 | c-doc2 | D-2 | `CLAUDE.md` | none | none |
| 22 | c-doc3 | D-3 | `CLAUDE.md` | none | none |
| 23 | c-doc5 | D-5 | `docs/2026-05-31-yas-local-mvp.md` | none | none |
| 24 | c-doc6 | D-6 | `test/job_queue_retry_test.dart` | (assertion tightening) | none |
| 25 | c-doc7 | D-7 | `test/grading_test.dart` (rename) | none | none |
| 26 | c-doc8 | D-8 | `test/rich_content_test.dart` | (assertion tightening) | none |
| 27 | c-doc9a | D-9a | `test/identify_screen_test.dart` (new) | new file | low |
| 28 | c-doc9b | D-9b | `test/create_task_screen_test.dart` (new) | new file | low |
| 29 | c-doc9c | D-9c | `test/home_screen_test.dart` (new) | new file | low |
| 30 | c-doc10 | D-10 | `lib/services/debug/debug_service.dart` | `test/debug_service_test.dart` (additions) | low |
| 31 | c-final | (sync) | `CLAUDE.md` (acceptance) | none | none |

**Total**: 32 commits. U-15 / U-5 / U-19 / D-4 are skipped (audit-rejected). A-1 / A-4 covered by sister plan.

---

## 4. Test Plan Summary

| Test file | New cases | Covers |
|---|---|---|
| `test/debouncer_test.dart` | 3 | U-2 (debouncer: cancel, fire, dispose) |
| `test/paper_detail_slider_test.dart` | 2 | U-2 (slider writes once on release) |
| `test/paper_detail_maxpoints_test.dart` | 1 | U-3 (fallback to item maxPoints) |
| `test/strategy_review_confirm_test.dart` | 1 | U-6 (snackbar on last confirm) |
| `test/photo_cap_test.dart` | 2 | U-7 (cap enforced in both screens) |
| `test/task_detail_regrade_debounce_test.dart` | 1 | U-9 (dialog button guarded) |
| `test/home_perf_test.dart` | 1 | U-10 (single submissionsByTask pass) |
| `test/task_detail_regrade_dialog_test.dart` | 1 | U-12 (no "保留旧结果" button) |
| `test/strategy_provider_missing_rubric_test.dart` | 1 | U-14 (banner when rubric missing) |
| `test/chat_sheet_error_test.dart` | 1 | U-18 (snackbar on send fail) |
| `test/error_formatter_test.dart` | 4 | U-20 (URL truncation + `?key=` warn) |
| `test/qwen_service_retry_test.dart` (additions) | 1 | A-2 (transport error retry) |
| `test/json_extractor_test.dart` (additions) | 2 | A-3 (balanced-bracket scanner finds 2nd candidate) |
| `test/identify_screen_test.dart` | 3 | D-9a |
| `test/create_task_screen_test.dart` | 3 | D-9b |
| `test/home_screen_test.dart` | 2 | D-9c |
| `test/debug_service_test.dart` (additions) | 1 | D-10 (clear resets stats) |
| **Total new test cases** | **30** | |

**Sister-plan baseline**: 326 + 20 = 346 passing on `fix/selective-bug-fix`. After this plan: 346 + 30 = **376 passing**.

---

## 5. Risks & Mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | U-2 slider drag value flicker (drag updates local state, parent only gets final) | M | L | Local state lives in `_PaperDetailScreenState`; parent `Submission.items` still has final value. Manual E2E. |
| R2 | A-3 balanced-bracket scanner misses edge cases (escaped quotes in regex) | M | M | 2 new test cases (positive + adversarial). Manual E2E with real LLM output. |
| R3 | U-7 cap at 100 may be too low for some teachers | L | L | 100 is a generous cap; can bump in a future round. |
| R4 | Doc edits to `CLAUDE.md` may be re-merged away by the sister's c12 commit | L | L | c-final will re-read & re-fix. |
| R5 | c-ux18 chat_sheet_error_test needs a way to inject a failing notifier | L | L | Pass a `SendMessage` callback override (sealed) — pattern already used elsewhere. |
| R6 | Dark theme surfaces existing "white-bg with default text" widgets that look broken | M | M | Out of scope to fix all surfaces in this round. c-ux1 enables the theme; the visual sweep is a follow-up. CLAUDE.md will note this. |
| R7 | U-1 darkTheme + `feedback_white_bg_black_text.md` may conflict | M | M | Memory still applies; no new violations. |

---

## 6. Out of Scope (explicitly NOT in this plan)

- A-1 (covered by sister c4d)
- A-4 (same root cause as C-1, covered by sister c1)
- C-*, S-* (all covered by sister)
- U-5 (audit-rejected; per-question filter is correct)
- U-15 (covered by sister c11)
- U-19 (audit-rejected; `Image.file` placeholder is fine)
- D-4 (audit-rejected; debug export DOES exist)
- The visual sweep of dark-mode-enabled widgets (R6) — follow-up round
- Unifying `_retryingRequest` and `refineStrategy` (A-2 full unification) — follow-up round
- A streaming JSON parser (A-3 full unification) — follow-up round

---

## 7. Acceptance Criteria

- [ ] 32 commits, each referencing `bbbbbiiiigBugs.md#<id>` in the message body
- [ ] `flutter test` shows 346 + 30 = 376 passing, 0 failing
- [ ] `flutter analyze` shows ≤ 1 info
- [ ] `flutter run -d macos` + manual E2E (smoke test of changed screens)
- [ ] `docs/audits/2026-06-06-little-bug-verdict.md` exists
- [ ] CLAUDE.md updated: c-final sync, darkTheme note, mutex location, log filename, image size doc
- [ ] README.md updated: log filename only
- [ ] `docs/2026-05-31-yas-local-mvp.md` banner + 10-route list
- [ ] No `qwen_*.log` references remain in any committed Markdown
- [ ] `test/grading_test.dart` renamed to `test/checkpoint_math_test.dart`
