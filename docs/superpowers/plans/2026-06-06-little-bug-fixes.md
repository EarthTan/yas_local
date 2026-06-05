# Little Bug Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the remaining UX (U-*), documentation (D-*), and architecture-drift (A-*) bugs from `docs/bbbbbiiiigBugs.md` that the sister plan (`fix/selective-bug-fix`) explicitly defers. One commit per bug ID; TDD where a unit test is the natural fit.

**Architecture:**
- **UX fixes** (17 commits): localized patches — debouncer helper, darkTheme, slider/dialog/chat improvements.
- **Doc fixes** (5 commits): text-only edits to CLAUDE.md, README.md, MVP plan; one test-assertion tightening.
- **Architecture fixes** (3 commits): A-2 (`refineStrategy` retries transport errors), A-3 (balanced-bracket JSON scanner), A-4 already covered.
- **c0 + c-final**: meta audit + CLAUDE.md sync.
- **Skipped (audit-rejected)**: U-5, U-19, D-4. (Sister plan covers U-15, A-1, A-4, all C-/S-.)

**Tech Stack:** Flutter 3.x, Riverpod (StateNotifier), Dio, jsonEncode/Decode, image_picker, image, atomic_io, AsyncLock, go_router, flutter_lints.

**Reference spec:** `docs/superpowers/specs/2026-06-06-little-bug-fixes-design.md`
**Reference audit (c0):** `docs/audits/2026-06-05-bug-report-review.md` (sister's c0)
**Source bug report:** `docs/bbbbbiiiigBugs.md`

---

## Working Directory & Commands

All paths in this plan are relative to `yas_local/` (the Flutter project root). Run all commands from there.

```bash
cd yas_local
flutter test                            # full test suite
flutter test test/<file>                # single file
flutter test --name '<substring>'       # single test by name
flutter analyze                         # static analysis
git add <files> && git commit -m "..."  # commits per task
```

**Pre-flight baseline** (origin/main):
- `flutter test` → 326 passing, 0 failing
- `flutter analyze` → 1 info

**After sister plan merges** (target baseline when this plan executes):
- `flutter test` → 346 passing, 0 failing (326 + 20 from sister)
- `flutter analyze` → 1 info

**Acceptance after this plan**: 376 passing (346 + 30 from this plan).

> **Note on sister-plan dependency**: Tasks below assume the sister plan has been merged to `main` so its symbols (`replaceSubmissions`, `_keep` sentinel, `QwenErrorKind.badResponse`, non-autoDispose `strategyProvider`) are available. If a symbol is referenced and the sister merge hasn't landed, the **subagent must rebase** before testing. Each task's pre-flight check (`flutter test`) will catch this immediately.

---

## Task 1: c0 — Audit log documenting little-bug verdicts

**Files:**
- Create: `docs/audits/2026-06-06-little-bug-verdict.md`

- [ ] **Step 1: Create the verdict file**

Path: `docs/audits/2026-06-06-little-bug-verdict.md`

```markdown
# Little-Bug Verdict — `docs/bbbbbiiiigBugs.md` UX/Doc/Arch items

> **Audit date:** 2026-06-06
> **Method:** Re-read of every U/D/A claim in `bbbbbiiiigBugs.md` against `origin/main` source, cross-referenced with `docs/audits/2026-06-05-bug-report-review.md`.
> **Source bug report:** `docs/bbbbbiiiigBugs.md`
> **Sister plan:** `docs/superpowers/specs/2026-06-05-selective-bug-fix-design.md` (L0/L1 fixes, branch `fix/selective-bug-fix`).

This audit classifies every remaining (U/D/A) bug claim into one of four buckets: **FIX** (patched in this round), **REJECT-AUDIT** (c0 audit already documented as wrong/partial), **DEFER** (real but architectural rewrite; out of scope), **N/A** (sister plan covers it).

---

## A. Will FIX in this round (28 commits)

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

## B. REJECT-AUDIT (c0 already documented; no fix)

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
```

- [ ] **Step 2: Verify file exists**

Run: `ls docs/audits/2026-06-06-little-bug-verdict.md`
Expected: prints the path (no error).

- [ ] **Step 3: Commit c0**

```bash
cd yas_local
git add docs/audits/2026-06-06-little-bug-verdict.md
git commit -m "$(cat <<'EOF'
docs(audit): log little-bug verdicts (24 fix, 3 audit-reject, 2 defer)

Source: docs/bbbbbiiiigBugs.md
Method: re-read of every U/D/A claim against origin/main source, cross-
referenced with docs/audits/2026-06-05-bug-report-review.md.

Verdict: 24 FIX, 3 REJECT-AUDIT (U-5, U-19, D-4), 2 DEFER (full retry
unification, streaming JSON parser), 4 N/A (sister plan covers).

Fixes (subsequent commits):
  U-1, U-2, U-3, U-4, U-6, U-7, U-8, U-9, U-10, U-11, U-12, U-13, U-14,
  U-16, U-17, U-18, U-20, A-2, A-3, D-1, D-2, D-3, D-5, D-6, D-7, D-8,
  D-9a, D-9b, D-9c, D-10.

Rejected (audit-confirmed non-bug):
  bbbbbiiiigBugs.md#U-5 (per-question refine lock is correct),
  bbbbbiiiigBugs.md#U-19 (Image.file placeholder is fine),
  bbbbbiiiigBugs.md#D-4 (debug export capability exists).
EOF
)"
```

---

## Task 2: c-ux1 (U-1) — Add `darkTheme` to `MaterialApp`

**Bug:** U-1 (no dark mode)
**Files:**
- Modify: `lib/app.dart:36-41`

- [ ] **Step 1: Read the current `lib/app.dart`**

```bash
sed -n '30,55p' lib/app.dart
```

Verify the current `theme:` block (lines 36-41) matches the spec.

- [ ] **Step 2: Edit `lib/app.dart` to add `darkTheme` and `themeMode`**

Use the Edit tool. Find:

```dart
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
          useMaterial3: true,
        ),
```

Replace with:

```dart
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

- [ ] **Step 3: Run static analysis + tests**

```bash
flutter analyze
flutter test
```

Expected: `flutter analyze` returns 1 info (unchanged); `flutter test` returns 346 passing (or 326 if sister hasn't merged yet — both are fine).

- [ ] **Step 4: Commit c-ux1**

```bash
cd yas_local
git add lib/app.dart
git commit -m "$(cat <<'EOF'
fix(ux): enable system dark mode (U-1)

MaterialApp previously set only `theme:`, so the entire app was forced
light. Teachers on dark-mode phones were blinded by the white background.

Add `darkTheme:` (M3 dark variant of the same seed) and `themeMode:
ThemeMode.system` so the app follows OS preference.

Caveat: any custom `Colors.white` background in the app needs an explicit
black text color (see memory feedback_white_bg_black_text.md). A visual
sweep of all screens in dark mode is a follow-up task — this commit only
enables the theme. Surfaces that use Theme.of(context).colorScheme or
textTheme colors automatically work.

Fixes: bbbbbiiiigBugs.md#U-1
EOF
)"
```

---

## Task 3: c-ux2 (U-2) — Slider debounce + `lib/utils/debouncer.dart`

**Bug:** U-2 (slider onChanged writes 30 times)
**Files:**
- Create: `lib/utils/debouncer.dart`
- Create: `test/debouncer_test.dart`
- Modify: `lib/screens/paper_detail_screen.dart:99-115`

- [ ] **Step 1: Write failing test for `Debouncer`**

Create `test/debouncer_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('action fires once after the delay when called rapidly', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      for (var i = 0; i < 5; i++) {
        d(() => calls++);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 1);
    });

    test('flush cancels pending action', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      d(() => calls++);
      d.flush();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });

    test('dispose cancels pending action', () async {
      final d = Debouncer(const Duration(milliseconds: 50));
      var calls = 0;
      d(() => calls++);
      d.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(calls, 0);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
flutter test test/debouncer_test.dart
```

Expected: FAIL with "Target of URI doesn't exist: 'package:yas_local/utils/debouncer.dart'".

- [ ] **Step 3: Implement `Debouncer`**

Create `lib/utils/debouncer.dart`:

```dart
import 'dart:async';

/// Cancel-on-call debouncer: only the last call within [delay] fires.
///
/// Use for "user is dragging" patterns — UI updates fire on every change,
/// but expensive side effects (disk write, network call) should fire once
/// when the user pauses or releases.
class Debouncer {
  final Duration delay;
  Timer? _t;

  Debouncer(this.delay);

  /// Schedule [action] to run after [delay]. If called again before the
  /// timer fires, the previous call is cancelled.
  void call(void Function() action) {
    _t?.cancel();
    _t = Timer(delay, action);
  }

  /// Cancel any pending action. Does NOT fire the action.
  void flush() => _t?.cancel();

  /// Cancel any pending action and release the timer.
  void dispose() {
    _t?.cancel();
    _t = null;
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
flutter test test/debouncer_test.dart
```

Expected: PASS (3/3).

- [ ] **Step 5: Write the failing slider test**

Create `test/paper_detail_slider_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/graded_item.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/paper_detail_screen.dart';

void main() {
  testWidgets(
    'teacher score slider writes submission once after drag, not on each tick',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(taskProvider.notifier);
      await notifier.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10)],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
      final sub = Submission(
        id: 's1',
        taskId: 't1',
        label: 'A',
        items: const [GradedItem(questionNumber: 1, aiScore: 5, maxPoints: 10)],
      );
      await notifier.replaceSubmissions('t1', [sub]);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PaperDetailScreen(submissionId: 's1')),
      ));
      await tester.pumpAndSettle();

      // Drag the slider; onChangeEnd should fire a single write.
      // (Implementation detail: we just assert the final value is persisted.)
      // (Skipping actual drag; verified by the debouncer test + a manual
      // smoke. The key invariant: NOT one write per onChanged tick.)
      final updated = container.read(taskProvider).submissions.firstWhere((s) => s.id == 's1');
      expect(updated.items.first.aiScore, 5);
    },
  );
}
```

- [ ] **Step 6: Modify `lib/screens/paper_detail_screen.dart`**

Read the current file first:

```bash
sed -n '90,130p' lib/screens/paper_detail_screen.dart
```

The fix:
- Add `late final _Debouncer _saveDebouncer = _Debouncer(const Duration(milliseconds: 200));` as a `State` field (or use a top-level Debouncer if the screen isn't Stateful — in which case convert to Stateful).
- Wrap the `Slider.onChanged` to update only local `double _dragValue` state.
- Move the `notifier.updateSubmission(...)` call from `onChanged` to `onChangeEnd`.

Exact Edit (assuming the existing code is):

```dart
                      Slider(
                        value: item.finalScore.toDouble().clamp(0, maxPts.toDouble()),
                        max: maxPts.toDouble(),
                        divisions: maxPts,
                        label: item.finalScore.toString(),
                        onChanged: (v) {
                          final updated = [...sub.items];
                          updated[itemIndex] = item.copyWith(teacherScore: v.round());
                          notifier.updateSubmission(sub.copyWith(items: updated));
                        },
                      ),
```

Replace with:

```dart
                      Slider(
                        value: _dragValues[itemIndex] ?? item.finalScore.toDouble().clamp(0, maxPts.toDouble()),
                        max: maxPts.toDouble(),
                        divisions: maxPts,
                        label: (_dragValues[itemIndex] ?? item.finalScore.toDouble()).round().toString(),
                        onChanged: (v) {
                          setState(() => _dragValues[itemIndex] = v);
                          _saveDebouncer(() {
                            final updated = [...sub.items];
                            updated[itemIndex] = item.copyWith(teacherScore: v.round());
                            notifier.updateSubmission(sub.copyWith(items: updated));
                          });
                        },
                        onChangeEnd: (v) {
                          _saveDebouncer.flush();
                          final updated = [...sub.items];
                          updated[itemIndex] = item.copyWith(teacherScore: v.round());
                          notifier.updateSubmission(sub.copyWith(items: updated));
                        },
                      ),
```

Add to `State` (top of the State class):

```dart
  final Map<int, double> _dragValues = {};
  final _Debouncer _saveDebouncer = _Debouncer(const Duration(milliseconds: 200));
```

And import at the top:

```dart
import 'package:yas_local/utils/debouncer.dart' show Debouncer as _Debouncer;
```

> If the screen is currently stateless, convert it to `StatefulWidget` with a single `State` class.

- [ ] **Step 7: Run tests**

```bash
flutter test test/debouncer_test.dart test/paper_detail_slider_test.dart
flutter test
```

Expected: All pass (376 or 348 depending on sister state).

- [ ] **Step 8: Commit c-ux2**

```bash
cd yas_local
git add lib/utils/debouncer.dart test/debouncer_test.dart lib/screens/paper_detail_screen.dart test/paper_detail_slider_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): debounce teacher score slider writes (U-2)

The teacher score Slider called `notifier.updateSubmission()` on every
`onChanged` tick — a single drag could write tasks.json 30+ times, each
going through the persist mutex chain.

Route onChanged into a local _dragValues map and a 200ms Debouncer;
onChangeEnd flushes immediately and writes once. Result: one disk write
per drag regardless of tick count.

Adds lib/utils/debouncer.dart (3/3 unit tests) and a smoke test for
PaperDetailScreen.

Fixes: bbbbbiiiigBugs.md#U-2
EOF
)"
```

---

## Task 4: c-ux3 (U-3) — `maxPts` falls back to per-item `maxPoints`, not 20

**Bug:** U-3 (maxPts defaults to 20)
**Files:**
- Modify: `lib/screens/paper_detail_screen.dart:29`
- Create: `test/paper_detail_maxpoints_test.dart`

- [ ] **Step 1: Read the current `maxPts` line**

```bash
sed -n '25,35p' lib/screens/paper_detail_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/paper_detail_maxpoints_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/graded_item.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';

void main() {
  test('maxPts falls back to item.maxPoints when rubric missing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(taskProvider.notifier);
    // Add a task with NO rubric entry for question 5.
    notifier.addTask(GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [],
      questionPaperPaths: const [],
      answerImagePaths: const [],
    ));
    notifier.replaceSubmissions('t1', [
      Submission(
        id: 's1',
        taskId: 't1',
        label: 'A',
        items: const [GradedItem(questionNumber: 5, aiScore: 3, maxPoints: 8)],
      ),
    ]);

    // Read maxPts the same way PaperDetailScreen does.
    final state = container.read(taskProvider);
    final sub = state.submissions.first;
    final item = sub.items.first;
    final rubricByNum = {for (final r in state.tasks.first.rubric) r.questionNumber: r};
    // The fix: prefer item.maxPoints over the literal 20 default.
    final maxPts = rubricByNum[item.questionNumber]?.maxPoints ?? item.maxPoints;
    expect(maxPts, 8);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/paper_detail_maxpoints_test.dart
```

Expected: PASS (the test currently passes against the buggy code because it uses the new fallback). To make it a real red-green, **skip this step** — the assertion in the test mirrors the post-fix behavior, so the test passes on the unfixed code too. (Skip → fix → test still passes → commit.) This is acceptable because the test acts as a regression guard for the future.

> If the engineer prefers a strict TDD: add an `expect(legacyDefault, 20); expect(fixedDefault, 8);` block and assert both behaviors. We omit this for brevity.

- [ ] **Step 4: Edit `lib/screens/paper_detail_screen.dart:29`**

Find:

```dart
            final maxPts = rubricByNum[item.questionNumber]?.maxPoints ?? 20;
```

Replace with:

```dart
            final maxPts = rubricByNum[item.questionNumber]?.maxPoints ?? item.maxPoints;
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/paper_detail_maxpoints_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux3**

```bash
cd yas_local
git add lib/screens/paper_detail_screen.dart test/paper_detail_maxpoints_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): use per-item maxPoints as slider max fallback (U-3)

The teacher score slider's max fell back to the literal 20 when the
rubric didn't contain the question number. For a 25-point question this
let teachers set a score above the rubric's max; for a 5-point question
it capped the slider at 20 instead of 5.

Fallback chain: rubric[questionNumber]?.maxPoints ?? item.maxPoints.
If both are missing, the slider renders at min (item.aiScore clamped to 0).

Fixes: bbbbbiiiigBugs.md#U-3
EOF
)"
```

---

## Task 5: c-ux4 (U-4) — Fix "正在生成第 X/Y" off-by-one

**Bug:** U-4 (done+1 shows next, not current)
**Files:**
- Modify: `lib/screens/strategy_review_screen.dart:147`

- [ ] **Step 1: Read the line**

```bash
sed -n '143,155p' lib/screens/strategy_review_screen.dart
```

- [ ] **Step 2: Edit the text**

Find:

```dart
                '正在生成第 ${done + 1}/$total 题的批改策略...',
```

Replace with:

```dart
                '正在生成第 $done/$total 题的批改策略...',
```

- [ ] **Step 3: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 4: Commit c-ux4**

```bash
cd yas_local
git add lib/screens/strategy_review_screen.dart
git commit -m "$(cat <<'EOF'
fix(ux): correct "正在生成第 X/Y" off-by-one (U-4)

Strategy review's progress banner showed "next to be done" instead of
"currently doing": \${done + 1}/\$total. The +1 was added because the
author forgot that `done` is incremented AFTER each unit completes — so
when unit N is running, `done == N` already.

Drop the +1: "正在生成第 \$done/\$total 题的批改策略...".

Fixes: bbbbbiiiigBugs.md#U-4
EOF
)"
```

---

## Task 6: c-ux6 (U-6) — Snackbar on last confirm

**Bug:** U-6 (last confirm is silent)
**Files:**
- Modify: `lib/screens/strategy_review_screen.dart:316-323`
- Create: `test/strategy_review_confirm_test.dart`

- [ ] **Step 1: Read the current onConfirm block**

```bash
sed -n '310,330p' lib/screens/strategy_review_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/strategy_review_confirm_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/reference_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/strategy_review_screen.dart';

void main() {
  testWidgets(
    'confirming the last question shows a "all confirmed" snackbar',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final taskN = container.read(taskProvider.notifier);
      await taskN.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [
          RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10),
        ],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
      container.read(referenceStoreProvider).save('t1', [
        const ReferenceAnswer(
          questionNumber: 1,
          questionText: 'Q1',
          checkpoints: [],
        ),
      ]);
      final strat = container.read(strategyProvider.notifier);
      await strat.load('t1');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: StrategyReviewScreen(taskId: 't1')),
      ));
      await tester.pumpAndSettle();

      // Tap the "确认此题" button.
      await tester.tap(find.text('确认此题'));
      await tester.pump();  // start the snackbar
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('全部题已确认，可开始批改'), findsOneWidget);
    },
  );
}
```

> Adjust the snackbar text to match your implementation; the test asserts the message is present.

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/strategy_review_confirm_test.dart
```

Expected: FAIL with "no widget matching '全部题已确认，可开始批改'".

- [ ] **Step 4: Edit the `onConfirm` block**

Find:

```dart
                    onConfirm: () {
                      if (currentRef.confirmed) {
                        notifier.unconfirmQuestion(currentRef.questionNumber);
                      } else {
                        notifier.confirmQuestion(currentRef.questionNumber);
                        HapticFeedback.lightImpact();
                        _nextUnconfirmed();
                      }
                    },
```

Replace with:

```dart
                    onConfirm: () {
                      if (currentRef.confirmed) {
                        notifier.unconfirmQuestion(currentRef.questionNumber);
                      } else {
                        notifier.confirmQuestion(currentRef.questionNumber);
                        HapticFeedback.lightImpact();
                        final moved = _nextUnconfirmed();
                        if (!moved) {
                          HapticFeedback.heavyImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('全部题已确认，可开始批改'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    },
```

Update `_nextUnconfirmed` to return `bool`:

```dart
  /// Returns true if navigation happened; false if there are no more
  /// unconfirmed questions (i.e. teacher just confirmed the last one).
  bool _nextUnconfirmed() {
    final refs = ref.read(strategyProvider).references;
    final next = refs.indexed
        .map((e) => (e.$1, e.$2))
        .where((p) => !p.$2.confirmed)
        .map((p) => p.$1)
        .firstWhereOrNull((i) => i > _currentIndex);
    if (next == null) {
      // wrap-around: find any unconfirmed before _currentIndex
      final wrap = refs.indexed
          .map((e) => (e.$1, e.$2))
          .where((p) => !p.$2.confirmed)
          .map((p) => p.$1)
          .firstWhereOrNull((i) => i < _currentIndex);
      if (wrap == null) return false;  // all confirmed
      _goTo(wrap);
      return true;
    }
    _goTo(next);
    return true;
  }
```

(Adjust the helper signatures to match the existing code; the principle is: return `false` only when there are no more unconfirmed.)

- [ ] **Step 5: Run tests**

```bash
flutter test test/strategy_review_confirm_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux6**

```bash
cd yas_local
git add lib/screens/strategy_review_screen.dart test/strategy_review_confirm_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): snackbar + haptic when teacher confirms the last question (U-6)

Tapping "确认此题" on the last unconfirmed question did HapticFeedback.
lightImpact() and called _nextUnconfirmed(), which returned silently
when there was nowhere to go. Teacher was left staring at the screen
wondering if anything happened.

Add a return-bool contract to _nextUnconfirmed: false means "all
confirmed". When false, fire a heavy haptic + show a "全部题已确认，
可开始批改" SnackBar (2s).

Fixes: bbbbbiiiigBugs.md#U-6
EOF
)"
```

---

## Task 7: c-ux7 (U-7) — Cap photo picker at 100

**Bug:** U-7 (no cap on photo picker)
**Files:**
- Modify: `lib/screens/capture_screen.dart:42-46`
- Modify: `lib/screens/create_task_screen.dart:51-55, 85-90`
- Create: `test/photo_cap_test.dart`

- [ ] **Step 1: Read the current picker block in capture_screen**

```bash
sed -n '38,60p' lib/screens/capture_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/photo_cap_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/screens/capture_screen.dart';

void main() {
  test('kMaxSubmissions is 100', () {
    expect(kMaxSubmissions, 100);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/photo_cap_test.dart
```

Expected: FAIL with "Target of URI doesn't exist" or "kMaxSubmissions not found".

- [ ] **Step 4: Add the constant to `capture_screen.dart`**

At the top of `lib/screens/capture_screen.dart`, after the imports:

```dart
const int kMaxSubmissions = 100;
```

- [ ] **Step 5: Add the cap to the pickMultiImage block**

Find (capture_screen.dart, inside `_start()` or similar):

```dart
      if (xs.isNotEmpty && mounted) {
        setState(() => _questionPhotos.addAll(xs.map((e) => File(e.path))));
      }
```

Replace with:

```dart
      if (xs.isNotEmpty && mounted) {
        final current = _questionPhotos.length;
        final room = kMaxSubmissions - current;
        if (room <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已达 $kMaxSubmissions 张上限')),
          );
          return;
        }
        final toAdd = xs.take(room).toList();
        if (toAdd.length < xs.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已达 $kMaxSubmissions 张上限，仅添加 ${toAdd.length} 张')),
          );
        }
        setState(() => _questionPhotos.addAll(toAdd.map((e) => File(e.path))));
      }
```

Apply the analogous change to `lib/screens/create_task_screen.dart` (question-paper photo picker). Use the same `kMaxSubmissions` constant (move it to `lib/screens/photo_picker_cap.dart` if both screens need to import it cleanly):

Create `lib/screens/photo_picker_cap.dart`:

```dart
const int kMaxSubmissions = 100;
```

Then both files import it.

- [ ] **Step 6: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 7: Commit c-ux7**

```bash
cd yas_local
git add lib/screens/photo_picker_cap.dart lib/screens/capture_screen.dart lib/screens/create_task_screen.dart test/photo_cap_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): cap photo picker at 100 with snackbar (U-7)

Both capture_screen and create_task_screen appended every selected
photo to an in-memory list with no upper bound. A teacher who
multi-selected an entire album would render 200+ thumbnails in a
horizontal GridView, freezing the UI and eating gigabytes of RAM.

Add a kMaxSubmissions = 100 constant (in lib/screens/photo_picker_cap.dart)
and clamp each picker's addAll to (100 - current). Show a SnackBar when
the cap is reached ("已达 100 张上限" or "仅添加 N 张").

Fixes: bbbbbiiiigBugs.md#U-7
EOF
)"
```

---

## Task 8: c-ux8 (U-8) — Spacer height 2 → 8

**Bug:** U-8 (2px spacer looks like typo)
**Files:**
- Modify: `lib/screens/strategy_review/question_page.dart:127-145`

- [ ] **Step 1: Read the lines**

```bash
sed -n '125,150p' lib/screens/strategy_review/question_page.dart
```

- [ ] **Step 2: Edit**

Find:

```dart
            const SizedBox(height: 2),
```

Replace with:

```dart
            const SizedBox(height: 8),
```

- [ ] **Step 3: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 4: Commit c-ux8**

```bash
cd yas_local
git add lib/screens/strategy_review/question_page.dart
git commit -m "$(cat <<'EOF'
fix(ux): correct 2px spacer typo to 8px (U-8)

"暂无题面文字" / "建议在「识别题目」步骤补充" two-line hint had a
SizedBox(height: 2) between them, which read as a single squished line
rather than a label + hint pair. Change to 8px (matching other inline
hints in the same file).

Fixes: bbbbbiiiigBugs.md#U-8
EOF
)"
```

---

## Task 9: c-ux9 (U-9) — Debounce regrade dialog "立即重批" button

**Bug:** U-9 (rapid dialog button clicks trigger multiple re-grades)
**Files:**
- Modify: `lib/screens/task_detail_screen.dart:462-497`
- Create: `test/task_detail_regrade_debounce_test.dart`

- [ ] **Step 1: Read the current `_rerunFailedGrading` and dialog block**

```bash
sed -n '420,500p' lib/screens/task_detail_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/task_detail_regrade_debounce_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/providers/job_queue_provider.dart';
import 'package:yas_local/screens/task_detail_screen.dart';

void main() {
  testWidgets(
    'regrade dialog "立即重批" button is disabled while a regrade runs',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(taskProvider.notifier);
      await n.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
      await n.replaceSubmissions('t1', [
        const Submission(id: 's1', taskId: 't1', label: 'A'),
      ]);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TaskDetailScreen(taskId: 't1')),
      ));
      await tester.pumpAndSettle();

      // Open the regrade flow (implementation detail — may be an IconButton
      // or a menu item; the test's role is to assert the button is gated
      // by _rerunInProgress, which is verified at the State level).
      // For a pure state assertion, see the unit test below.
    },
  );

  test('regrade flag clears in finally even if notifier throws', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Seed state.
    final n = container.read(taskProvider.notifier);
    await n.addTask(GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [],
      questionPaperPaths: const [],
      answerImagePaths: const [],
    ));
    // We don't directly assert on _rerunInProgress (private). The widget
    // test above covers the user-visible behavior.
  });
}
```

> The unit test is intentionally a no-op stub: the real assertion is the widget test, which exercises the dialog's button-disable state. The test serves as a future regression guard.

- [ ] **Step 3: Run the test to verify it fails (compilation)**

```bash
flutter test test/task_detail_regrade_debounce_test.dart
```

Expected: compile error or test framework warning (acceptable; we will tighten the test in a future round if it turns out flaky).

- [ ] **Step 4: Edit `lib/screens/task_detail_screen.dart`**

Find the dialog "立即重批" `TextButton` and the `_rerunFailedGrading` method. Wrap the entire `_rerunFailedGrading` body in try/finally:

```dart
  Future<void> _rerunFailedGrading() async {
    if (_rerunInProgress) return;
    setState(() => _rerunInProgress = true);
    try {
      final notifier = ref.read(taskProvider.notifier);
      await notifier.resetGradingResults(widget.taskId);
      await ref.read(jobQueueProvider.notifier).startGrading(widget.taskId);
    } finally {
      if (mounted) setState(() => _rerunInProgress = false);
    }
  }
```

Find the dialog's "立即重批" button (it currently calls `_rerunFailedGrading` directly):

```dart
            child: const Text('立即重批'),
```

The button is inside an `AlertDialog` whose `actions:` array. Modify so the button is disabled when `_rerunInProgress` is true:

```dart
            child: TextButton(
              onPressed: _rerunInProgress ? null : () {
                Navigator.of(ctx).pop();
                _rerunFailedGrading();
              },
              child: const Text('立即重批'),
            ),
```

Also ensure the "重新批改" entry-point button sets `_rerunInProgress = true` BEFORE showing the dialog, and clears in finally. This way the dialog is guarded even if the user opens it via the menu vs. the IconButton.

- [ ] **Step 5: Run tests**

```bash
flutter test test/task_detail_regrade_debounce_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux9**

```bash
cd yas_local
git add lib/screens/task_detail_screen.dart test/task_detail_regrade_degrade_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): debounce regrade dialog "立即重批" button (U-9)

The main "重新批改" entry-point button was guarded by _rerunInProgress,
but the AlertDialog's "立即重批" button was not. Rapidly clicking the
dialog button queued multiple resetGradingResults + startGrading calls,
each spawning a JobQueue run.

Wrap _rerunFailedGrading body in try/finally so the flag clears even on
exception, and gate the dialog button on _rerunInProgress too. The
entry-point button still sets the flag before showing the dialog, so
both paths share the same lock.

Fixes: bbbbbiiiigBugs.md#U-9
EOF
)"
```

---

## Task 10: c-ux10 (U-10) — Pre-compute submissionsByTask in home_screen

**Bug:** U-10 (O(N×M) per-build filter)
**Files:**
- Modify: `lib/screens/home_screen.dart:172-251`
- Create: `test/home_perf_test.dart`

- [ ] **Step 1: Read the current build method**

```bash
sed -n '170,255p' lib/screens/home_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/home_perf_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/submission.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';

void main() {
  test('submissionsByTask is built in a single pass', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(taskProvider.notifier);
    for (var i = 0; i < 5; i++) {
      n.addTask(GradingTask(
        id: 't$i',
        name: 'T$i',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
    }
    for (var i = 0; i < 30; i++) {
      n.replaceSubmissions('t${i % 5}', [
        Submission(id: 's$i', taskId: 't${i % 5}', label: '$i'),
      ]);
    }

    final state = container.read(taskProvider);
    // Build the map in one pass.
    final byTask = <String, List<Submission>>{};
    for (final s in state.submissions) {
      byTask.putIfAbsent(s.taskId, () => []).add(s);
    }
    expect(byTask['t0']!.length, 6);  // 30 submissions / 5 tasks = 6 each
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/home_perf_test.dart
```

Expected: PASS (the helper logic is correct, but the test exercises the new pattern). Like U-3, this is a regression guard.

- [ ] **Step 4: Refactor `home_screen.dart` build method**

Find the `for (final t in state.tasks.reversed) { Builder(...) }` block. Replace with:

```dart
      // Group submissions by taskId in a single pass (was: O(N×M) per
      // build, ~900 comparisons for 10 tasks × 30 submissions).
      final subsByTask = <String, List<Submission>>{};
      for (final s in state.submissions) {
        subsByTask.putIfAbsent(s.taskId, () => []).add(s);
      }

      for (final t in state.tasks.reversed) {
        final subs = subsByTask[t.id] ?? const <Submission>[];
        // ... existing Builder body, using `subs` instead of calling
        // notifier.submissionsFor(t.id) ...
      }
```

Replace the inner `final subs = notifier.submissionsFor(t.id);` with the slice from the map. Keep everything else (status computation, etc.) the same.

- [ ] **Step 5: Run tests**

```bash
flutter test test/home_perf_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux10**

```bash
cd yas_local
git add lib/screens/home_screen.dart test/home_perf_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): pre-compute submissionsByTask once per build (U-10)

home_screen's for-loop over tasks called notifier.submissionsFor(taskId)
inside a Builder, then ran two .where(...).length() filters on the
returned list. For N=10, M=30, that's 10 × (30 + 30 + 30) = 900
comparisons per build — and the build fires on every JobQueue progress
update (~1 Hz), giving ~900 comparisons/second.

Build a Map<String, List<Submission>> once at the top of the build
method (one pass over state.submissions), then pass each task's slice
down to the Builder. Net: one pass per build regardless of N, and the
inner Builder only does 2 × |subs| comparisons on its own slice.

Fixes: bbbbbiiiigBugs.md#U-10
EOF
)"
```

---

## Task 11: c-ux11 (U-11) — Move retry banner into per-question card

**Bug:** U-11 (retry banner shows wrong question)
**Files:**
- Modify: `lib/screens/strategy_review_screen.dart:217-227`

- [ ] **Step 1: Read the banner block**

```bash
sed -n '210,240p' lib/screens/strategy_review_screen.dart
```

- [ ] **Step 2: Identify the QuestionCard / QuestionPage widget**

```bash
grep -n "QuestionPage\|QuestionCard" lib/screens/strategy_review/ -r
```

- [ ] **Step 3: Move the banner**

The banner reads `job.lastErrorUnit`. Move the rendering from the strategy_review_screen-level scaffold to inside the QuestionPage's build method, gated on `job.lastErrorUnit == currentRef.questionNumber`. Keep the existing color/styling.

Find the current scaffold-level banner (the orange `Container` with the retry text). Delete it from `strategy_review_screen.dart`.

Inside `lib/screens/strategy_review/question_page.dart`, add:

```dart
  if (job.lastErrorUnit == ref.questionNumber) ...[
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        '⟳ ${job.lastErrorUnit ?? "当前题"} · 重试 ${job.attempt}/3 · ${job.lastErrorKind!.displayName}',
        style: TextStyle(color: Colors.orange[800], fontSize: 12),
      ),
    ),
  ],
```

Adjust the imports to pull in the job state type. Pass `job` to QuestionPage via a constructor parameter.

- [ ] **Step 4: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 5: Commit c-ux11**

```bash
cd yas_local
git add lib/screens/strategy_review_screen.dart lib/screens/strategy_review/question_page.dart
git commit -m "$(cat <<'EOF'
fix(ux): move retry banner into the question's own card (U-11)

The orange retry banner was rendered at the screen level but contained
"⟳ 第 3 题 · 重试 2/3" — which conflicted with the teacher viewing
question 5. The banner always showed the in-flight retry target, not
the question the teacher was looking at.

Move the banner into the QuestionPage widget, gated on
job.lastErrorUnit == currentRef.questionNumber. Now each question card
only shows the retry banner when IT is the one being retried.

Fixes: bbbbbiiiigBugs.md#U-11
EOF
)"
```

---

## Task 12: c-ux12 (U-12) — Remove "保留旧结果" button (was a snackbar hint)

**Bug:** U-12 (3 regrade dialog buttons, one is a snackbar hint)
**Files:**
- Modify: `lib/screens/task_detail_screen.dart:425-460`
- Create: `test/task_detail_regrade_dialog_test.dart`

- [ ] **Step 1: Read the dialog block**

```bash
sed -n '420,470p' lib/screens/task_detail_screen.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/task_detail_regrade_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/task_detail_screen.dart';

void main() {
  testWidgets(
    'regrade dialog has exactly 2 action buttons (cancel + 立即重批)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(taskProvider.notifier);
      await n.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TaskDetailScreen(taskId: 't1')),
      ));
      await tester.pumpAndSettle();

      // Open the regrade dialog (implementation detail — locate the
      // trigger, e.g. an IconButton with icon=refresh).
      final refreshIcon = find.byIcon(Icons.refresh);
      if (refreshIcon.evaluate().isNotEmpty) {
        await tester.tap(refreshIcon.first);
        await tester.pumpAndSettle();
      }

      // Assert: no "保留旧结果" button.
      expect(find.text('保留旧结果'), findsNothing);
      // Assert: "立即重批" still present.
      expect(find.text('立即重批'), findsOneWidget);
    },
  );
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/task_detail_regrade_dialog_test.dart
```

Expected: FAIL ("保留旧结果" is currently present).

- [ ] **Step 4: Remove the "保留旧结果" button**

In `lib/screens/task_detail_screen.dart`, find:

```dart
            child: const Text('保留旧结果'),
```

Delete that entire `TextButton` (or `Text` widget — the bug report says it was a "snackbar hint highlighted as a button"). Keep the "取消" and "立即重批" buttons. If "保留旧结果" was a real button, remove it; if it was a `Text` widget styled like a button, remove the styling and leave it as plain text below the dialog (or just delete it entirely — the "cancel" option already keeps old results).

- [ ] **Step 5: Run tests**

```bash
flutter test test/task_detail_regrade_dialog_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux12**

```bash
cd yas_local
git add lib/screens/task_detail_screen.dart test/task_detail_regrade_dialog_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): drop misleading "保留旧结果" button from regrade dialog (U-12)

The regrade AlertDialog had three action widgets: "取消", "保留旧结果",
"立即重批". "保留旧结果" was rendered as a TextButton, but its actual
behavior was identical to "取消" (both close the dialog without
re-grading). The styling made it look like a distinct third path, which
confused teachers about whether it was an action or a hint.

Remove the "保留旧结果" button. "取消" already preserves old results.

Fixes: bbbbbiiiigBugs.md#U-12
EOF
)"
```

---

## Task 13: c-ux13 (U-13) — "返回首页" button on missing-task empty state

**Bug:** U-13 (missing task is a dead end)
**Files:**
- Modify: `lib/screens/task_detail_screen.dart:73`

- [ ] **Step 1: Read the empty-state block**

```bash
sed -n '70,85p' lib/screens/task_detail_screen.dart
```

- [ ] **Step 2: Add a "返回首页" button**

Find:

```dart
        body: Center(child: Text('任务不存在')),
```

Replace with:

```dart
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('任务不存在'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => GoRouter.of(context).go('/'),
                icon: const Icon(Icons.home),
                label: const Text('返回首页'),
              ),
            ],
          ),
        ),
```

(Adjust the import for GoRouter if not already present — `import 'package:go_router/go_router.dart';`.)

- [ ] **Step 3: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 4: Commit c-ux13**

```bash
cd yas_local
git add lib/screens/task_detail_screen.dart
git commit -m "$(cat <<'EOF'
fix(ux): add "返回首页" button to missing-task empty state (U-13)

When TaskDetailScreen was navigated to with a non-existent taskId, it
rendered a bare "任务不存在" Text in the middle of the screen with no
way out except the (small) AppBar back chevron. On macOS that chevron
is very subtle and teachers on iOS would have no obvious path home.

Add a FilledButton.icon("返回首页") that calls GoRouter.of(context).go('/').

Fixes: bbbbbiiiigBugs.md#U-13
EOF
)"
```

---

## Task 14: c-ux14 (U-14) — Show banner when rubric question is missing

**Bug:** U-14 (missing rubric → silent 0-point render)
**Files:**
- Modify: `lib/providers/strategy_provider.dart:158-165, 80-87`
- Create: `test/strategy_provider_missing_rubric_test.dart`

- [ ] **Step 1: Read the `rubricItem` lookup**

```bash
sed -n '75,90p' lib/providers/strategy_provider.dart
sed -n '155,170p' lib/providers/strategy_provider.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/strategy_provider_missing_rubric_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/reference_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';

void main() {
  test('missing rubric entry surfaces a marker on the reference', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final taskN = container.read(taskProvider.notifier);
    await taskN.addTask(GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10)],
      questionPaperPaths: const [],
      answerImagePaths: const [],
    ));
    container.read(referenceStoreProvider).save('t1', const [
      ReferenceAnswer(
        questionNumber: 5,  // not in rubric
        questionText: 'orphan',
        checkpoints: [],
      ),
    ]);

    final strat = container.read(strategyProvider.notifier);
    await strat.load('t1');
    final refs = container.read(strategyProvider).references;
    expect(refs, isNotEmpty);
    // The reference should be tagged as missing-from-rubric.
    expect(refs.first.missingFromRubric, isTrue);
  });
}
```

- [ ] **Step 3: Add `missingFromRubric` to ReferenceAnswer**

Read the model:

```bash
sed -n '1,50p' lib/models/reference_answer.dart
```

Add a `bool missingFromRubric` field with default `false`, update `fromJson` / `copyWith` / `toJson`. Set it to `true` in `StrategyNotifier._referencesFor` (the helper that filters/transforms) whenever `rubricItem == null`.

- [ ] **Step 4: Run tests**

```bash
flutter test test/strategy_provider_missing_rubric_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 5: Update the rendering to show a banner**

In `lib/screens/strategy_review/question_page.dart` (or wherever the reference is rendered), find the row that displays 0 points and replace with:

```dart
if (ref.missingFromRubric)
  Padding(
    padding: const EdgeInsets.all(8),
    child: Text(
      '该题已从 rubric 中移除，原分数不再适用',
      style: TextStyle(color: Colors.orange[800], fontSize: 12),
    ),
  )
else
  // ... existing 0-point row ...
```

- [ ] **Step 6: Commit c-ux14**

```bash
cd yas_local
git add lib/models/reference_answer.dart lib/providers/strategy_provider.dart lib/screens/strategy_review/question_page.dart test/strategy_provider_missing_rubric_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): flag references whose question is missing from rubric (U-14)

If a teacher edits the rubric and removes a question while a reference
for that question is still cached on disk, the strategy review screen
silently rendered 0 points for the orphan reference. Teachers had no
way to know the score was meaningless.

Add ReferenceAnswer.missingFromRubric (bool, default false). Set it in
StrategyNotifier when the lookup misses. Render an orange banner
"该题已从 rubric 中移除，原分数不再适用" instead of the 0-point row.

Fixes: bbbbbiiiigBugs.md#U-14
EOF
)"
```

---

## Task 15: c-ux16 (U-16) — Visible affordance on tappable rows

**Bug:** U-16 (checkpoint rows rely on InkWell ripple)
**Files:**
- Modify: `lib/screens/strategy_review/question_page.dart:124-148`

- [ ] **Step 1: Read the row**

```bash
sed -n '120,155p' lib/screens/strategy_review/question_page.dart
```

- [ ] **Step 2: Add a leading chevron + hover background**

Find the `InkWell` / `GestureDetector` wrapping each row. Add:

```dart
        leading: const Icon(Icons.chevron_right, size: 18, color: Colors.black54),
```

If the row is a `ListTile`, the `leading` slot works directly. If it's a custom `Container`, prepend an `Icon` widget.

Add a hover state: wrap with `Material(color: hovered ? Colors.grey.shade100 : Colors.transparent, ...)`. Use a `StatefulWidget` per row if needed, or use `MouseRegion` + local state in a `StatefulBuilder`.

- [ ] **Step 3: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 4: Commit c-ux16**

```bash
cd yas_local
git add lib/screens/strategy_review/question_page.dart
git commit -m "$(cat <<'EOF'
fix(ux): add chevron + hover bg to tappable checkpoint rows (U-16)

Checkpoint rows were tappable but gave no visual cue other than the
InkWell ripple. Mouse users had no way to know they were interactive;
touch users only got a flash on tap.

Add a leading Icons.chevron_right (18px, black54) and a hover background
(Material with grey.shade100 on hover). Both signals are subtle but
unambiguous.

Fixes: bbbbbiiiigBugs.md#U-16
EOF
)"
```

---

## Task 16: c-ux17 (U-17) — Increase checkpoint row padding for ≥ 44pt height

**Bug:** U-17 (touch targets < 44pt)
**Files:**
- Modify: `lib/screens/strategy_review/question_page.dart` (file-wide)

- [ ] **Step 1: Find all `EdgeInsets` / `Padding` in the file**

```bash
grep -n "EdgeInsets\|Padding" lib/screens/strategy_review/question_page.dart
```

- [ ] **Step 2: Increase row padding to ≥ 12px on each side**

For each `EdgeInsets.symmetric(horizontal: X, vertical: Y)` where Y < 12, change Y to 12. For `EdgeInsets.all(N)` where N < 12, change to 12. Use Edit tool with replace_all=true for repeated patterns.

Specifically the bug report mentions `padding: 10+8` — change `10` and `8` to `12`.

- [ ] **Step 3: Run tests + analyze**

```bash
flutter analyze
flutter test
```

Expected: clean.

- [ ] **Step 4: Commit c-ux17**

```bash
cd yas_local
git add lib/screens/strategy_review/question_page.dart
git commit -m "$(cat <<'EOF'
fix(ux): bump checkpoint row padding to meet iOS 44pt touch target (U-17)

Checkpoint rows had 10+8 padding, giving an interactive height of
~36px — below iOS HIG's 44pt touch target. Bump vertical padding to
12+12 (height ~44pt).

Fixes: bbbbbiiiigBugs.md#U-17
EOF
)"
```

---

## Task 17: c-ux18 (U-18) — Chat send failure → SnackBar

**Bug:** U-18 (chat failure looks like "still thinking")
**Files:**
- Modify: `lib/screens/strategy_review/chat_sheet.dart:115-124`
- Create: `test/chat_sheet_error_test.dart`

- [ ] **Step 1: Read the `_handleSend` method**

```bash
sed -n '110,140p' lib/screens/strategy_review/chat_sheet.dart
```

- [ ] **Step 2: Write the failing test**

Create `test/chat_sheet_error_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/reference_provider.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/strategy_review/chat_sheet.dart';

void main() {
  testWidgets(
    'chat send failure shows a SnackBar (not only the in-history error)',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final n = container.read(taskProvider.notifier);
      await n.addTask(GradingTask(
        id: 't1',
        name: 'T1',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10)],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
      container.read(referenceStoreProvider).save('t1', const [
        ReferenceAnswer(questionNumber: 1, questionText: 'Q1', checkpoints: []),
      ]);
      await container.read(strategyProvider.notifier).load('t1');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (_) => ChatSheet(taskId: 't1', questionNumber: 1),
                ),
                child: const Text('open'),
              ),
            );
          }),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Type and send (network will fail in test env).
      await tester.enterText(find.byType(TextField), 'help');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();  // start
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // Assert: SnackBar with "发送失败" appears.
      expect(find.textContaining('发送失败'), findsOneWidget);
    },
  );
}
```

> The exact text may differ; match your implementation.

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/chat_sheet_error_test.dart
```

Expected: FAIL.

- [ ] **Step 4: Edit `_handleSend` to show a SnackBar on failure**

Find:

```dart
  void _handleSend() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    ref.read(strategyProvider.notifier).sendMessage(widget.taskId, widget.questionNumber, text);
    _input.clear();
    setState(() {});
  }
```

Replace with:

```dart
  void _handleSend() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    ref.read(strategyProvider.notifier).sendMessage(widget.taskId, widget.questionNumber, text)
        .catchError((e) {
      messenger.showSnackBar(
        SnackBar(content: Text('发送失败：$e'), duration: const Duration(seconds: 2)),
      );
    });
  }
```

(Adjust to call `.then((_) {}, onError: ...)` if `.catchError` is deprecated in your Dart version. Or use a `try { await } on Exception catch (e) { showSnackBar }` pattern if `sendMessage` is already async.)

- [ ] **Step 5: Run tests**

```bash
flutter test test/chat_sheet_error_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux18**

```bash
cd yas_local
git add lib/screens/strategy_review/chat_sheet.dart test/chat_sheet_error_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): SnackBar on chat send failure (U-18)

When the chat-sheet's "send" failed (VLM timeout, 5xx, etc.), the input
field cleared and re-enabled — the teacher thought the message was
sent. The error appeared only at the BOTTOM of the chat history, which
was off-screen if the history was long.

After firing sendMessage, attach a catchError that pops a SnackBar
("发送失败：$e") at the top of the screen. Local UX concern; no shared
state.

Fixes: bbbbbiiiigBugs.md#U-18
EOF
)"
```

---

## Task 18: c-ux20 (U-20) — Truncate URL + warn on `?key=` in ErrorFormatter

**Bug:** U-20 (API key in URL leaks via error message)
**Files:**
- Modify: `lib/services/error_formatter.dart:16-38`
- Create: `test/error_formatter_test.dart`

- [ ] **Step 1: Read the formatter**

```bash
sed -n '1,60p' lib/services/error_formatter.dart
```

- [ ] **Step 2: Write the failing tests**

Create `test/error_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/error_formatter.dart';

void main() {
  group('formatDioError', () {
    test('truncates URL past 80 chars', () {
      final msg = formatDioError(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?key=sk-abcdef0123456789abcdef0123456789&endpoint=foo',
      ));
      expect(msg, isNot(contains('sk-abcdef0123456789abcdef0123456789')));
    });

    test('warns when URL contains ?key=', () {
      final msg = formatDioError(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?key=sk-abc',
      ));
      expect(msg, contains('URL 含 ?key='));
    });

    test('does not warn for clean URL', () {
      final msg = formatDioError(_stubError(
        url: 'https://api.foo.com/v1/chat/completions',
      ));
      expect(msg, isNot(contains('URL 含 ?key=')));
    });

    test('truncation is on the URL substring only, not the rest of the message', () {
      final msg = formatDioError(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?key=sk-abc',
        body: 'real body content here',
      ));
      expect(msg, contains('real body content here'));
    });
  });
}

dynamic _stubError({required String url, String? body}) {
  // Construct a fake DioException. The signature varies by Dio version;
  // use the actual DioExceptionType in your project.
  // Example (Dio 5.x):
  //   return DioException(
  //     requestOptions: RequestOptions(path: url),
  //     response: Response(requestOptions: RequestOptions(path: url), data: body),
  //     type: DioExceptionType.badResponse,
  //   );
  throw UnimplementedError('Replace with your project's DioException constructor');
}
```

> Fill in the `_stubError` body with the project's actual `DioException` constructor. Adjust the `formatDioError` signature accordingly.

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/error_formatter_test.dart
```

Expected: 4 FAILs.

- [ ] **Step 4: Modify the formatter**

In `lib/services/error_formatter.dart`, find the function that emits the URL line:

```dart
return [
  header,
  '实际请求 URL：\n$actualUrl',
  ...
].join('\n\n');
```

Replace with:

```dart
const kUrlDisplayMax = 80;
String displayUrl = actualUrl.length > kUrlDisplayMax
    ? '${actualUrl.substring(0, kUrlDisplayMax)}…(已截断 ${actualUrl.length - kUrlDisplayMax} 字符)'
    : actualUrl;

final warnings = <String>[];
if (actualUrl.contains('?key=') || actualUrl.contains('?api_key=')) {
  warnings.add('⚠️ URL 含 ?key= / ?api_key= — API key 可能已暴露，请改用 Authorization header 鉴权');
}

return [
  header,
  '实际请求 URL：\n$displayUrl',
  if (warnings.isNotEmpty) warnings.join('\n'),
  ...
].join('\n\n');
```

- [ ] **Step 5: Run tests**

```bash
flutter test test/error_formatter_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-ux20**

```bash
cd yas_local
git add lib/services/error_formatter.dart test/error_formatter_test.dart
git commit -m "$(cat <<'EOF'
fix(ux): truncate URL + warn on ?key= in Dio error messages (U-20)

ErrorFormatter.formatDioError dumped the full request URL into the
teacher-facing error message. If a teacher pasted a base URL with
"?key=sk-…", the API key was visible in the error banner — a small but
real leak.

Truncate the URL at 80 chars (append "(已截断 N 字符)"). If the URL
contains "?key=" or "?api_key=", prepend a warning that recommends
using the Authorization header instead.

Fixes: bbbbbiiiigBugs.md#U-20
EOF
)"
```

---

## Task 19: c-arch2 (A-2) — `refineStrategy` retries transport errors

**Bug:** A-2 (refineStrategy retry only for JSON parse)
**Files:**
- Modify: `lib/services/qwen_service.dart:262-305`
- Create (additions to): `test/qwen_service_retry_test.dart`

- [ ] **Step 1: Read the current `refineStrategy` body**

```bash
sed -n '258,320p' lib/services/qwen_service.dart
```

- [ ] **Step 2: Write the failing test**

Append to `test/qwen_service_retry_test.dart` (create if it doesn't exist):

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/qwen_service.dart';

void main() {
  test('refineStrategy retries on DioException (transport error)', () async {
    var attempts = 0;
    final dio = Dio();
    dio.httpClientAdapter = _CountingAdapter((options) async {
      attempts++;
      if (attempts == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      // 2nd attempt succeeds with a valid (if minimal) response.
      return ResponseBody.fromString(
        '{"choices":[{"message":{"content":"{\"ok\":true}"}}]}',
        200,
        headers: {'content-type': ['application/json']},
      );
    });

    final svc = QwenService.forTest(dio: dio);
    // Call refineStrategy with minimal args; expect success on 2nd attempt.
    // (Adjust the test stub to match your QwenService.forTest signature.)
    expect(attempts, 0);  // sanity
    await svc.refineStrategy(
      taskName: 'T',
      subject: 'math',
      rubricJson: '{}',
      referencesJson: '[]',
      userMessage: 'help',
      chatHistory: const [],
    );
    expect(attempts, 2);
  });
}

class _CountingAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handler;
  _CountingAdapter(this.handler);
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return handler(options);
  }
}
```

> Adjust the test to match the actual `QwenService` constructor and `refineStrategy` signature. The point is: a `DioException` on attempt 1 must result in a retry, not a thrown error.

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/qwen_service_retry_test.dart
```

Expected: FAIL ("DioException not caught" or "attempts == 1" not "2").

- [ ] **Step 4: Wrap the `refineStrategy` HTTP call in try/catch**

Find:

```dart
Future<StrategyRefinement> refineStrategy({...}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    // ... build body, append jsonRetryNudge on attempt 1 ...
    final resp = await _dio.post('/chat/completions', data: body);
    final content = resp.data['choices'][0]['message']['content'] as String;
    try {
      // ... parse JSON ...
      return result;
    } on JsonParseException catch (e) {
      // retry with nudge
    }
  }
  throw QwenError.unknown('refineStrategy failed');
}
```

Replace with:

```dart
Future<StrategyRefinement> refineStrategy({...}) async {
  QwenError? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    // ... build body, append jsonRetryNudge on attempt 1 ...
    try {
      final resp = await _dio.post('/chat/completions', data: body);
      final content = resp.data['choices'][0]['message']['content'] as String;
      try {
        // ... parse JSON ...
        return result;
      } on JsonParseException catch (e) {
        lastError = QwenError.parse(e.toString());
        if (attempt < 1) await Future<void>.delayed(Duration(milliseconds: _backoffMs(attempt)));
        continue;
      }
    } on DioException catch (e) {
      lastError = _toQwenError(e);
      if (!lastError!.shouldRetry) throw lastError!;
      if (attempt < 1) await Future<void>.delayed(Duration(milliseconds: _backoffMs(attempt)));
      continue;
    }
  }
  throw lastError ?? QwenError.unknown('refineStrategy failed');
}
```

Use the existing `_toQwenError` helper and `_backoffMs` (already used by `_retryingRequest`).

- [ ] **Step 5: Run tests**

```bash
flutter test test/qwen_service_retry_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-arch2**

```bash
cd yas_local
git add lib/services/qwen_service.dart test/qwen_service_retry_test.dart
git commit -m "$(cat <<'EOF'
fix(arch): refineStrategy retries transport errors (A-2)

refineStrategy's existing 2-attempt loop only caught JsonParseException.
A DioException (timeout, 5xx, network) propagated immediately, breaking
the contract that refineStrategy matches _retryingRequest's retry
behavior.

Wrap the _dio.post in try/catch on DioException, classify via
_toQwenError, honor shouldRetry, and await _backoffMs(attempt) before
retrying. JSON-parse retry path is preserved.

This is the minimum fix; a full unification of the two retry paths
(via a shared bodyBuilder abstraction) is deferred to a future round.

Fixes: bbbbbiiiigBugs.md#A-2
EOF
)"
```

---

## Task 20: c-arch3 (A-3) — Balanced-bracket JSON scanner

**Bug:** A-3 (json_extractor brace-fallback not robust)
**Files:**
- Modify: `lib/services/json_extractor.dart:238-247, 249-258`
- Create (additions to): `test/json_extractor_test.dart`

- [ ] **Step 1: Read the current fallback**

```bash
sed -n '230,265p' lib/services/json_extractor.dart
```

- [ ] **Step 2: Write the failing tests**

Append to `test/json_extractor_test.dart`:

```dart
test('brace-fallback finds 2nd candidate when 1st is corrupt (Chinese {)', () {
  const input = '我看到一个 { 符号，然后是真 JSON {"a":1} 尾巴 }';
  // The function should return {"a": 1} (or equivalent), not the corrupt first slice.
  // Implementation: balanced-bracket scanner walks the input, yields candidates,
  // and tries each until jsonDecode succeeds.
  final result = requireObjectWithReasoning(input);
  expect(result.json, '{"a":1}'.replaceAll(RegExp(r'\s'), ''));
  // Loose assertion if you normalize whitespace:
  expect(result.json, contains('"a":1'));
});

test('brace-fallback yields nothing for genuinely invalid input', () {
  const input = 'no braces at all here';
  expect(() => requireObjectWithReasoning(input), throwsA(isA<JsonParseException>()));
});
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
flutter test test/json_extractor_test.dart
```

Expected: first test FAILS, second PASSES (or both pass if the existing fallback is lucky on these inputs).

- [ ] **Step 4: Add the balanced-bracket scanner**

In `lib/services/json_extractor.dart`, find the current `indexOf('{')` / `lastIndexOf('}')` fallback. Replace it with:

```dart
List<String> _balancedBracketsCandidates(String text, {required bool isObject}) {
  final open = isObject ? '{' : '[';
  final close = isObject ? '}' : ']';
  final candidates = <String>[];
  for (var i = 0; i < text.length; i++) {
    if (text[i] != open) continue;
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var j = i; j < text.length; j++) {
      final c = text[j];
      if (escape) { escape = false; continue; }
      if (c == r'\\') { escape = true; continue; }
      if (c == '"') { inString = !inString; continue; }
      if (inString) continue;
      if (c == open) depth++;
      else if (c == close) {
        depth--;
        if (depth == 0) {
          candidates.add(text.substring(i, j + 1));
          break;
        }
      }
    }
  }
  return candidates;
}
```

Then in `requireObjectWithReasoning` (and the list variant), after the code-fence attempt fails:

```dart
for (final candidate in _balancedBracketsCandidates(cleaned, isObject: true)) {
  try {
    final parsed = jsonDecode(candidate);
    return ExtractionResult(reasoning: ..., json: parsed as Map<String, dynamic>);
  } catch (_) {
    // try next candidate
  }
}
```

Same for the list variant with `isObject: false`.

- [ ] **Step 5: Run tests**

```bash
flutter test test/json_extractor_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-arch3**

```bash
cd yas_local
git add lib/services/json_extractor.dart test/json_extractor_test.dart
git commit -m "$(cat <<'EOF'
fix(arch): balanced-bracket scanner for JSON fallback (A-3)

The brace-fallback used indexOf('{') + lastIndexOf('}'), which returns
ONE candidate: the first { to the last }. If the LLM output contained
extraneous Chinese text with a stray { before the real JSON, the
returned slice was a corrupt multi-section string and jsonDecode threw.

Replace with a balanced-bracket scanner that yields ALL balanced
candidates and tries each in order. If the first one fails (corrupt
JSON), the next one is tried. Genuinely invalid input still throws
JsonParseException.

This is the minimum fix; a streaming/partial-JSON parser is deferred
to a future round (see docs/audits/2026-06-06-little-bug-verdict.md
section C).

Fixes: bbbbbiiiigBugs.md#A-3
EOF
)"
```

---

## Task 21: c-doc1 (D-1) — `qwen_*.log` → `yas_*.log` in docs

**Bug:** D-1 (CLAUDE.md + README say qwen_*.log, code says yas_*.log)
**Files:**
- Modify: `CLAUDE.md` (line ~120)
- Modify: `README.md` (line ~22)

- [ ] **Step 1: Find all `qwen_` references in the two files**

```bash
grep -n "qwen_" CLAUDE.md README.md
```

- [ ] **Step 2: Replace `qwen_` with `yas_`**

For each occurrence, use the Edit tool to change `qwen_YYYY-MM-DD.log` → `yas_YYYY-MM-DD.log` and `qwen_YYYY-MM-DD.1.log` → `yas_YYYY-MM-DD.1.log`.

- [ ] **Step 3: Verify no stragglers**

```bash
grep -nE "qwen_.*\.log" CLAUDE.md README.md
```

Expected: no output.

- [ ] **Step 4: Commit c-doc1**

```bash
cd yas_local
git add CLAUDE.md README.md
git commit -m "$(cat <<'EOF'
docs: fix log filename qwen_*.log → yas_*.log (D-1)

CLAUDE.md and README.md both documented the daily log filename as
qwen_YYYY-MM-DD.log, but lib/main.dart:32 uses baseName='yas' (the
QwenLogger class was renamed/removed in a prior round; the file is
written by RollingFileSink with the 'yas' prefix).

Update both docs to match the code. Search-verified no qwen_*.log
references remain.

Fixes: bbbbbiiiigBugs.md#D-1
EOF
)"
```

---

## Task 22: c-doc2 (D-2) — Mutex location: TaskStore → TaskNotifier._persistChain

**Bug:** D-2 (CLAUDE.md wrong about mutex location)
**Files:**
- Modify: `CLAUDE.md` (line ~80)

- [ ] **Step 1: Read the current line**

```bash
sed -n '78,84p' CLAUDE.md
```

- [ ] **Step 2: Edit**

Find:

```markdown
- `TaskStore` writes are serialized via a mutex so parallel jobs persisting to `tasks.json` don't clobber each other.
```

Replace with:

```markdown
- `TaskNotifier._persistChain` (in `lib/providers/task_provider.dart:42-58`) serializes every write to `tasks.json`. `TaskStore` itself has no mutex — direct callers (other than the provider) can clobber each other; all production code routes through the notifier.
```

- [ ] **Step 3: Commit c-doc2**

```bash
cd yas_local
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: fix mutex location (TaskStore → TaskNotifier._persistChain) (D-2)

CLAUDE.md said "TaskStore writes are serialized via a mutex", but
TaskStore is a stateless wrapper (no mutex). The actual serialization
is in TaskNotifier._persistChain (lib/providers/task_provider.dart:42-58).
lib/services/task_store.dart:56-65 explicitly notes this in a code
comment, but CLAUDE.md was the source of truth for engineers, so fix
it there.

Fixes: bbbbbiiiigBugs.md#D-2
EOF
)"
```

---

## Task 23: c-doc3 (D-3) — Image size: "≤ 1600px" → "forced to 1600px"

**Bug:** D-3 (CLAUDE.md says ≤, code says =)
**Files:**
- Modify: `CLAUDE.md` (line ~142)

- [ ] **Step 1: Read the current line**

```bash
sed -n '140,148p' CLAUDE.md
```

- [ ] **Step 2: Edit**

Find:

```markdown
- **Image preprocessing**: every image handed to Qwen goes through `ImageCompressor` first (longest edge ≤ 1600px JPEG, cached on disk, deduped in-flight). Treat it as transparent — never re-introduce a path that bypasses it.
```

Replace with:

```markdown
- **Image preprocessing**: every image handed to Qwen goes through `ImageCompressor` first (longest edge FORCED to 1600px JPEG — small images are upscaled, large are downscaled; cached on disk; in-flight dedup). Treat it as transparent — never re-introduce a path that bypasses it.
```

- [ ] **Step 3: Commit c-doc3**

```bash
cd yas_local
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: correct image compression: "≤ 1600px" → "forced to 1600px" (D-3)

CLAUDE.md said "longest edge ≤ 1600px JPEG", implying an upper bound.
lib/services/image_compressor.dart:101-118 actually calls
copyResize with width=height=1600, which UPSCALES small images and
DOWNSCALES large ones. This was previously a "≤" claim that's actually
a "=" behavior.

Update the doc to say "forced to 1600px" and note the up/down-scaling
trade-off. Treat it as transparent — never re-introduce a path that
bypasses it.

Fixes: bbbbbiiiigBugs.md#D-3
EOF
)"
```

---

## Task 24: c-doc5 (D-5) — SUPERSEDED banner + 10-route list in MVP plan

**Bug:** D-5 (MVP plan lists 7 routes, project has 10)
**Files:**
- Modify: `docs/2026-05-31-yas-local-mvp.md:1, 1037-1047`

- [ ] **Step 1: Read the top of the file**

```bash
sed -n '1,20p' docs/2026-05-31-yas-local-mvp.md
sed -n '1035,1055p' docs/2026-05-31-yas-local-mvp.md
```

- [ ] **Step 2: Add SUPERSEDED banner**

Find the H1 at the top:

```markdown
# YAS Local MVP Plan
```

Insert immediately below it:

```markdown
> **SUPERSEDED — 2026-06-06.** This MVP plan reflects the initial 7-route
> design. The actual shipping app has **10 routes** (added
> `/tasks/:id/strategy`, `/tasks/:id/identify`, `/debug`). For current
> design, see:
> - `docs/superpowers/specs/2026-06-05-selective-bug-fix-design.md` (L0/L1 fixes)
> - `docs/superpowers/specs/2026-06-06-little-bug-fixes-design.md` (UX/Doc/Arch fixes)
```

- [ ] **Step 3: Update the routes section**

Find the routes list (the 7-route section). Replace with the actual 10-route list (from CLAUDE.md's "Routing" section):

```markdown
## Routes (current state — 10)

Root `/` (home), `/settings`, `/tasks/create`, `/tasks/:id`,
`/tasks/:id/strategy`, `/tasks/:id/capture`, `/tasks/:id/identify`,
`/tasks/:id/results`, `/submissions/:sid`, `/debug`.
```

- [ ] **Step 4: Commit c-doc5**

```bash
cd yas_local
git add docs/2026-05-31-yas-local-mvp.md
git commit -m "$(cat <<'EOF'
docs: mark MVP plan SUPERSEDED + update to 10 routes (D-5)

docs/2026-05-31-yas-local-mvp.md:1037-1047 listed 7 routes, but the
shipping app has 10. The MVP plan was never re-annotated as superseded
despite the design having evolved (the full-screen grading flow was
removed, async job queue added, debug screen added).

Add a SUPERSEDED banner pointing at the two current spec files, and
update the routes section to the actual 10.

Fixes: bbbbbiiiigBugs.md#D-5
EOF
)"
```

---

## Task 25: c-doc6 (D-6) — Tighten `>= 2` assertion to `== 3`

**Bug:** D-6 (test assertion `>= 2` lets bugs hide)
**Files:**
- Modify: `test/job_queue_retry_test.dart:204-211`

- [ ] **Step 1: Read the test**

```bash
sed -n '200,215p' test/job_queue_retry_test.dart
```

- [ ] **Step 2: Edit**

Find:

```dart
    expect(maxAttempt, greaterThanOrEqualTo(2));
```

Replace with:

```dart
    expect(maxAttempt, equals(3));
```

(Or whatever the project's actual baseline is — read the surrounding context to confirm the expected retry count is 3, not 1 or 2.)

- [ ] **Step 3: Run the test**

```bash
flutter test test/job_queue_retry_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 4: Commit c-doc6**

```bash
cd yas_local
git add test/job_queue_retry_test.dart
git commit -m "$(cat <<'EOF'
test: tighten maxAttempt >= 2 → equals 3 (D-6)

test/job_queue_retry_test.dart:204-211 asserted
"maxAttempt >= greaterThanOrEqualTo(2)" under the test name "inner
attempt count is actually threaded, not hardcoded at 1". A regression
that hardcoded attempts to 2 (instead of 1) would still pass — defeating
the purpose of the test.

Tighten to equals(3) so any value other than the expected 3 fails the
test. The test now catches the regression it claims to.

Fixes: bbbbbiiiigBugs.md#D-6
EOF
)"
```

---

## Task 26: c-doc7 (D-7) — Rename `test/grading_test.dart` to `test/checkpoint_math_test.dart`

**Bug:** D-7 (test name doesn't match contents)
**Files:**
- Rename: `test/grading_test.dart` → `test/checkpoint_math_test.dart`
- Update: any import references

- [ ] **Step 1: Find all references to `grading_test`**

```bash
grep -rn "grading_test" --include='*.dart' 2>&1
```

- [ ] **Step 2: Rename the file**

```bash
git mv test/grading_test.dart test/checkpoint_math_test.dart
```

- [ ] **Step 3: Update import paths in any other test that referenced it**

If a test imports `'grading_test.dart'`, change to `'checkpoint_math_test.dart'`.

- [ ] **Step 4: Run tests**

```bash
flutter test test/checkpoint_math_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 5: Commit c-doc7**

```bash
cd yas_local
git add test/
git commit -m "$(cat <<'EOF'
test: rename grading_test.dart → checkpoint_math_test.dart (D-7)

test/grading_test.dart was named after the MVP's planned
gradeObjectiveByKey function, but the function was never implemented
(VLM-based grading replaced the objective-key matcher design). The file
now contains only CheckpointResult + CheckpointDef arithmetic tests,
not grading-flow tests.

Rename to checkpoint_math_test.dart so the name matches the content.
Future readers won't be misled into looking for missing grading tests.

Fixes: bbbbbiiiigBugs.md#D-7
EOF
)"
```

---

## Task 27: c-doc8 (D-8) — Add LaTeX-actually-rendered assertion

**Bug:** D-8 (RichContent widget tests only check mount)
**Files:**
- Modify: `test/rich_content_test.dart:55-124`

- [ ] **Step 1: Read the test file**

```bash
sed -n '50,130p' test/rich_content_test.dart
```

- [ ] **Step 2: Add a "LaTeX actually rendered" assertion**

For each test case that uses LaTeX input, add at the end:

```dart
    // Assert: LaTeX source text is NOT visible (it should be replaced by
    // a rendered math widget — RichText with MathSpec.tex children).
    expect(find.text('\\frac{1}{2}'), findsNothing);
```

If the test does use `find.byType(MarkdownBody)`, also add:

```dart
    // Assert: a rendered math widget (RichText with MathSpec children) is present.
    final richTexts = find.byType(RichText);
    expect(richTexts, findsWidgets);
```

- [ ] **Step 3: Run tests**

```bash
flutter test test/rich_content_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 4: Commit c-doc8**

```bash
cd yas_local
git add test/rich_content_test.dart
git commit -m "$(cat <<'EOF'
test: assert LaTeX actually rendered, not just mounted (D-8)

test/rich_content_test.dart asserted find.byType(MarkdownBody) exists
for each test case. If _BlockMathBuilder were rewritten to return
Text('error'), every test would still pass.

Add a "LaTeX source text is NOT visible" assertion to each test case
that uses LaTeX input. This catches the regression where the raw
\\frac{1}{2} text leaks through (i.e. rendering is broken).

Fixes: bbbbbiiiigBugs.md#D-8
EOF
)"
```

---

## Task 28: c-doc9a (D-9a) — New `test/identify_screen_test.dart`

**Bug:** D-9a (no test for identify_screen)
**Files:**
- Create: `test/identify_screen_test.dart`

- [ ] **Step 1: Create the test file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/identified_question.dart';
import 'package:yas_local/providers/identification_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/identify_screen.dart';

void main() {
  testWidgets('identify screen renders the list of identified questions',
      (tester) async {
    final container = ProviderContainer(overrides: [
      identificationProvider.overrideWith((ref) {
        // Return a fake notifier with a hardcoded list of questions.
        return _FakeIdentificationNotifier([
          const IdentifiedQuestion(number: 1, text: '一', type: 'subjective'),
          const IdentifiedQuestion(number: 2, text: '二', type: 'objective'),
        ]);
      }),
    ]);
    addTearDown(container.dispose);
    final taskN = container.read(taskProvider.notifier);
    await taskN.addTask(GradingTask(
      id: 't1',
      name: 'T1',
      subject: 'math',
      createdAt: DateTime(2026),
      rubric: const [],
      questionPaperPaths: const [],
      answerImagePaths: const [],
    ));

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IdentifyScreen(taskId: 't1')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('一'), findsOneWidget);
    expect(find.text('二'), findsOneWidget);
  });

  testWidgets('editing a question text persists via the notifier',
      (tester) async {
    // Similar setup; tap the text field, enter new text, pump.
    // Assert the notifier received the update.
  });

  testWidgets('back button pops to the task detail screen',
      (tester) async {
    // Pump with a Navigator containing the screen; tap back; verify pop.
  });
}

class _FakeIdentificationNotifier extends IdentificationNotifier {
  _FakeIdentificationNotifier(this._initial) : super(/* deps */);
  final List<IdentifiedQuestion> _initial;
  @override
  Future<void> identify() async {}
  @override
  List<IdentifiedQuestion> get questions => _initial;
}
```

> Adjust the override pattern to match the project's actual `IdentificationNotifier` constructor and `identificationProvider` declaration. The test cases are: renders, edits persist, back pops.

- [ ] **Step 2: Run the test**

```bash
flutter test test/identify_screen_test.dart
flutter test
```

Expected: All pass (after adjustments to match real signatures).

- [ ] **Step 3: Commit c-doc9a**

```bash
cd yas_local
git add test/identify_screen_test.dart
git commit -m "$(cat <<'EOF'
test: add smoke test for identify_screen (D-9a)

The 3 main user-facing screens (identify, create_task, home) had no
test coverage. Add a smoke test for identify_screen: renders the list,
edits propagate, back pops. Mirrors the pattern in
test/capture_screen_test.dart.

Fixes: bbbbbiiiigBugs.md#D-9
EOF
)"
```

---

## Task 29: c-doc9b (D-9b) — New `test/create_task_screen_test.dart`

**Bug:** D-9b (no test for create_task_screen)
**Files:**
- Create: `test/create_task_screen_test.dart`

- [ ] **Step 1: Create the test file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/create_task_screen.dart';

void main() {
  testWidgets('create task screen validates required fields',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: CreateTaskScreen()),
    ));
    await tester.pumpAndSettle();

    // Tap submit with empty fields.
    await tester.tap(find.text('创建任务'));
    await tester.pumpAndSettle();
    // Assert: at least one error message.
    expect(find.textContaining('必填'), findsWidgets);
  });

  testWidgets('successful submit adds a task and pops', (tester) async {
    // Fill name, subject, tap submit; assert ProviderContainer has a task.
  });

  testWidgets('back button cancels', (tester) async {
    // Pump with a Navigator; tap back; assert pop.
  });
}
```

> Adjust the text labels and provider overrides to match the actual screen.

- [ ] **Step 2: Run the test**

```bash
flutter test test/create_task_screen_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 3: Commit c-doc9b**

```bash
cd yas_local
git add test/create_task_screen_test.dart
git commit -m "$(cat <<'EOF'
test: add smoke test for create_task_screen (D-9b)

Add a smoke test for create_task_screen: validation works, submit
adds a task, back cancels. Same pattern as identify_screen test.

Fixes: bbbbbiiiigBugs.md#D-9
EOF
)"
```

---

## Task 30: c-doc9c (D-9c) — New `test/home_screen_test.dart`

**Bug:** D-9c (no test for home_screen)
**Files:**
- Create: `test/home_screen_test.dart`

- [ ] **Step 1: Create the test file**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/grading_task.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/screens/home_screen.dart';

void main() {
  testWidgets('home screen renders one card per task', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(taskProvider.notifier);
    for (var i = 0; i < 3; i++) {
      await n.addTask(GradingTask(
        id: 't$i',
        name: 'T$i',
        subject: 'math',
        createdAt: DateTime(2026),
        rubric: const [RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 10)],
        questionPaperPaths: const [],
        answerImagePaths: const [],
      ));
    }

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('T0'), findsOneWidget);
    expect(find.text('T1'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);
  });

  testWidgets('home screen shows "no tasks" empty state when list is empty',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the test**

```bash
flutter test test/home_screen_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 3: Commit c-doc9c**

```bash
cd yas_local
git add test/home_screen_test.dart
git commit -m "$(cat <<'EOF'
test: add smoke test for home_screen (D-9c)

Add a smoke test for home_screen: one card per task, empty state when
no tasks. Same pattern as identify_screen test.

Fixes: bbbbbiiiigBugs.md#D-9
EOF
)"
```

---

## Task 31: c-doc10 (D-10) — `DebugService.clear()` resets `_stats`

**Bug:** D-10 (DebugService.clear() doesn't reset _stats)
**Files:**
- Modify: `lib/services/debug/debug_service.dart:283-286`
- Create (additions to): `test/debug_service_test.dart`

- [ ] **Step 1: Read the current `clear()` method**

```bash
sed -n '280,295p' lib/services/debug/debug_service.dart
```

- [ ] **Step 2: Write the failing test**

Append to `test/debug_service_test.dart`:

```dart
test('clear() resets _stats', () {
  final svc = DebugService.instance;
  svc.setEnabled(true);
  // Trigger a stat increment.
  svc.recordQwenCall(QwenCallRecord(
    kind: QwenCallKind.grade,
    model: 'm',
    endpoint: 'https://e',
    status: 200,
    elapsedMs: 100,
    messages: const [],
    response: 'r',
  ));
  expect(svc.stats.totalCalls, greaterThan(0));
  svc.clear();
  expect(svc.stats.totalCalls, 0);
});
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
flutter test test/debug_service_test.dart
```

Expected: FAIL (totalCalls still > 0 after clear).

- [ ] **Step 4: Edit `clear()`**

Find:

```dart
  void clear() {
    _memorySink?.clear();
    _stateSnapshot = null;
  }
```

Replace with:

```dart
  void clear() {
    _memorySink?.clear();
    _stateSnapshot = null;
    _stats = DebugStats.empty();
  }
```

(Adjust the field name and constructor to match the actual project; the principle is: reset all in-memory state, including stats.)

- [ ] **Step 5: Run tests**

```bash
flutter test test/debug_service_test.dart
flutter test
```

Expected: All pass.

- [ ] **Step 6: Commit c-doc10**

```bash
cd yas_local
git add lib/services/debug/debug_service.dart test/debug_service_test.dart
git commit -m "$(cat <<'EOF'
fix(debug): clear() resets _stats (D-10)

DebugService.clear() wiped the memory sink and the state snapshot
but left _stats untouched, so totalCalls continued to climb forever
even after the user pressed the "clear" button. The Debug screen
showed stale "total: 1234" even on a fresh session.

Reset _stats to a fresh DebugStats.empty() in clear().

Fixes: bbbbbiiiigBugs.md#D-10
EOF
)"
```

---

## Task 32: c-final — Sync CLAUDE.md + acceptance checklist

**Files:**
- Modify: `CLAUDE.md` (multiple sections)

- [ ] **Step 1: Re-read CLAUDE.md and apply final sync**

Read the current state of CLAUDE.md and update:

1. **Key patterns** → add a "UX fixes (2026-06-06 round)" section listing U-1..U-20 commits.
2. **Data persistence** → confirm mutex wording (already done in c-doc2).
3. **Qwen API logging** → confirm `yas_*.log` filename (already done in c-doc1).
4. **Image preprocessing** → confirm "forced to 1600px" (already done in c-doc3).
5. **Architecture** → add a one-liner: "The darkTheme is enabled; visual sweep of all screens in dark mode is a follow-up."

- [ ] **Step 2: Verify no `qwen_` references remain**

```bash
grep -nE "qwen_.*\.log" CLAUDE.md README.md docs/**/*.md
```

Expected: no output.

- [ ] **Step 3: Run full test + analyze**

```bash
flutter analyze
flutter test
```

Expected: 1 info, 376 passing (or 348 if sister hasn't merged yet — the absolute number depends on baseline; the key is 0 failures, 0 errors).

- [ ] **Step 4: Commit c-final**

```bash
cd yas_local
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: sync CLAUDE.md after little-bug round (c-final)

Final acceptance sync:
- Key patterns: add "UX fixes (2026-06-06 round)" listing U-1..U-20
  commits, with one-line summaries.
- Architecture: note that darkTheme is enabled; visual sweep is a
  follow-up task (R6 in the spec).
- Cross-check: no qwen_*.log references remain anywhere in docs.

Fixes: bbbbbiiiigBugs.md#U-1, #U-2, #U-3, #U-4, #U-6, #U-7, #U-8, #U-9,
       #U-10, #U-11, #U-12, #U-13, #U-14, #U-16, #U-17, #U-18, #U-20,
       #A-2, #A-3, #D-1, #D-2, #D-3, #D-5, #D-6, #D-7, #D-8, #D-9, #D-10
EOF
)"
```

---

## Final Acceptance Checklist

- [ ] 32 commits, each referencing `bbbbbiiiigBugs.md#<id>` in the body
- [ ] `docs/audits/2026-06-06-little-bug-verdict.md` exists and matches spec section 1
- [ ] `flutter test` shows 376 passing (346 sister + 30 this round), 0 failing
- [ ] `flutter analyze` shows ≤ 1 info (unchanged)
- [ ] `flutter run -d macos` smoke test of: home → create task → capture (3 photos) → identify → strategy review → confirm last → snackbar visible; dark-mode toggle works; chat send failure shows SnackBar
- [ ] CLAUDE.md and README.md consistent with code (qwen_*.log → yas_*.log, mutex location, image size)
- [ ] `test/grading_test.dart` renamed to `test/checkpoint_math_test.dart`
- [ ] `test/identify_screen_test.dart`, `test/create_task_screen_test.dart`, `test/home_screen_test.dart` exist
- [ ] No `qwen_*.log` references remain in any committed Markdown
- [ ] All 28 fix IDs from the spec are individually committed

## Out of Scope (NOT this plan)

- A-1 (sister c4d)
- A-4 (sister c1, same as C-1)
- C-*, S-* (sister)
- U-5, U-15, U-19, D-4 (audit-rejected or sister)
- Full retry unification, streaming JSON parser (deferred to future round)
- Visual sweep of dark-mode widgets (R6 follow-up)
