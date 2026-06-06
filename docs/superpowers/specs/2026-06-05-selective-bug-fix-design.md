# Selective Bug Fix — 14 CONFIRMED 0+1 Level Bugs

> **Source audit**: `docs/bbbbbiiiigBugs.md` (5 subagent code-read pass, 2026-06-05).
> **Strategy**: B (architectural root-cause for the 4 strategy bugs, localized patch for the other 10).
> **Discipline**: TDD (red-green-refactor), per-commit `flutter test` 326+ must stay green.
> **Traceability**: every commit message body references `bbbbbiiiigBugs.md#<id>` (claim ID + verdict).
>
> **Spec author**: brainstorming session, 2026-06-05.

---

## 0. Audit Summary (pre-fix)

| Verdict | Count | Action |
|---|---|---|
| ✅ CONFIRMED (real bug, fix selected) | 14 | Fix in this round |
| ⚠️ Partially CONFIRMED (less severe than claim) | 14 | Defer to future round (out of scope) |
| ❌ WRONG / unsubstantiated (claim was overstated, wrong, or refers to nonexistent code) | 6 | Document in c0, do not fix |

Selected bugs (the 14 this spec fixes) are 0-level (data loss) + 1-level (state corruption) per the audit. The 6 WRONG + 14 partial claims are listed in `docs/audits/2026-06-05-bug-report-review.md` (created in c0) for traceability.

**Selected bug IDs (15)**: C-1, C-2, C-3, C-4, C-5, C-9, S-4, S-5, S-6, S-7, S-8, S-9, S-10, S-12, U-15. Packing:
- 11 fix commits (c1, c2, c3, c5–c11) each address 1 ID
- 3 fix commits (c4a, c4b, c4c) each address 1 of {C-4, C-5, S-9} — the G4 root-cause
- 1 refactor commit (c4d) — non-autoDispose switch + debounce infrastructure, no new ID fixed
- → 11 + 3 + 1 = 15 fix slots covering 15 distinct IDs, in 14 commits

---

## 1. Bug Grouping (11 commits; 4 of them are G4's sub-commits)

| Commit | Group | Bug IDs (claim) | One-line fix |
|---|---|---|---|
| `c0`  | audit | (none — meta) | Independent `docs/audits/2026-06-05-bug-report-review.md` + commit message log of 6 WRONG + 14 partial claims with evidence |
| `c1`  | G1    | C-1 | Rename `setSubmissions` → `replaceSubmissions`; add confirm dialog "将覆盖之前的 N 份" in capture_screen |
| `c2`  | G2    | C-2 | `readJsonOrQuarantine` becomes per-item: one bad record is renamed aside with type+index scope, the rest are kept |
| `c3`  | G3    | C-3, S-10, C-9 | Tolerant `fromJson` for `CheckpointDef` + `StrategyMessage`; `ImageCompressor._inflight` cleans up via `whenComplete` |
| `c4a` | G4a   | C-4 | `StrategyNotifier` non-autoDispose; debounced `ReferenceStore.save` after every checkpoint edit/add/remove; `saveAllConfirmed` flushes the debounce |
| `c4b` | G4b   | C-5 | Same debounced save hooked into `sendMessage` (chat refinement) |
| `c4c` | G4c   | S-9 | In-flight token guard: `int _token` bumped on `dispose()`; each async method captures token before await; if `myToken != _token` after await, return without writing state |
| `c4d` | G4d   | (none — refactor, addresses A-1 naming) | Remove `autoDispose` from `strategyProvider` so notifier survives navigation; add `flushPendingSave()` API + `WidgetsBindingObserver` in `main.dart` for app-lifecycle flush. This commit names the architectural root cause (A-1) but does not fix a new bug — the fixes are c4a/b/c. |
| `c5`  | G5    | S-4 | `pointsAwarded` clamped to `[0, checkpointDef.points]` in `qwen_service._parseReferenceAnswer` (and the list-graded path uses the same constant) |
| `c6`  | G6    | S-5 | Cancelled job: `_patch` checks `cancelRequested` first; phase = `failed`, error = "用户已取消" |
| `c7`  | G7    | S-6 | Add explicit `List<QuestionGradeResult>` generic on `_retryWithFeedback<List<QuestionGradeResult>>(...)` |
| `c8`  | G8    | S-7 | `GradedItem.copyWith` tri-state: `Object? teacherScore = _keep` sentinel; explicit `clearTeacherScore: true` parameter as the only way to null it out. **No UI is added** — `paper_detail_screen.dart` still only sets via the slider; clearing a teacher override is currently a programmatic-only capability, intended for future "撤销我的改分" UI |
| `c9`  | G9    | S-8 | Re-grade dialog button reuses `_rerunInProgress`; on dialog open the screen state is set true until either path resolves |
| `c10` | G10   | S-12 | New `QwenErrorKind.badResponse` enum value; `badResponse` no longer falls into `unknown`; `shouldRetry` for `badResponse` = false |
| `c11` | G11   | U-15 | `_initEditables` disposes the existing list before clear/addAll |
| `c12` | docs  | (none) | Sync `CLAUDE.md` to reflect: per-item quarantine policy, `strategyProvider` is non-autoDispose, debounced save, `GradedItem.copyWith` tri-state, `QwenErrorKind.badResponse`, `checkpointDef` clamp in `qwen_service` |

Total: **15 commits** (c0 meta, c1-c11 fix + 1 G4-refactor c4d, c12 docs).

---

## 2. Architecture Changes

### 2.1 G2 — Per-Item Quarantine

**Before** (`lib/services/atomic_io.dart:61-106` + `lib/services/task_store.dart:23-35`):

```
tasks.json
  → jsonDecode (raw)
  → decode(parsed): for each item, .fromJson()  ← one throw quarantines the WHOLE file
  → StoreData(tasks, subs)
```

Quarantine = file renamed to `tasks.json.broken.<scope>.<pid>.<micros>.<counter>`, original gone.

**After**:

```
tasks.json
  → jsonDecode (raw)  ← failure still quarantines the whole file (genuine corruption, not per-item)
  → decode(parsed): for each item, try { fromJson(...) } catch { _quarantineOne(file, item, type) }
  → returns only the items that parsed cleanly
```

Per-item quarantine renames the original `tasks.json` to `.broken.<type>.<index>.<…>` (the original **file is still gone** for that moment), then **immediately re-writes the surviving items back to `tasks.json` atomically via `writeJsonAtomic`**. The teacher keeps working with k-1 (or k-m) items instead of 0. The .broken file is exposed in `/debug` so a teacher can recover it manually if it was a transient parse error.

**API change**:

```dart
// atomic_io.dart
Future<T> readJsonOrQuarantine<T>(...) // unchanged signature

// NEW: per-item isolate + atomic re-write
Future<void> _quarantineAndRewrite(
  File file,
  List<int> survivors,            // indices that parsed cleanly
  String typeName,                // 'submission' | 'reference' | 'task'
)
```

**CLAUDE.md change** (line 80 area):

> ~~"TaskStore writes are serialized via a mutex…"~~
> → "TaskStore reads use **per-item quarantine**: one bad record ≠ whole file lost. The bad record is renamed aside (debug screen exposes the .broken file path) and the surviving records are atomically re-written back. Writes are serialized via `TaskNotifier._persistChain` in `task_provider.dart:42-58`."

### 2.2 G4 — `StrategyNotifier` Lifecycle Rewrite

**Before** (`lib/providers/strategy_provider.dart:359-362`):

```dart
final strategyProvider =
    StateNotifierProvider.autoDispose<StrategyNotifier, StrategyState>((ref) {
      return StrategyNotifier(ref, qwenFactory: ref.read(qwenFactoryProvider));
    });
```

**After**:

```dart
final strategyProvider =
    StateNotifierProvider<StrategyNotifier, StrategyState>((ref) {
      return StrategyNotifier(ref, qwenFactory: ref.read(qwenFactoryProvider));
    });
```

`strategyProvider` joins `taskProvider` / `jobQueueProvider` / `settingsProvider` — never auto-disposed. Riverpod holds the instance for the app's lifetime.

**`StrategyNotifier` shape**:

```dart
class StrategyNotifier extends StateNotifier<StrategyState> {
  int _token = 0;                          // bumped on dispose()
  Timer? _saveDebounce;
  String? _saveTaskId;                     // for flush on app pause

  // ── lifecycle ────────────────────────────────────────
  @override
  void dispose() {
    _token++;                              // invalidates in-flight
    _saveDebounce?.cancel();               // best-effort
    super.dispose();
  }

  void _scheduleSave(String taskId) {
    _saveDebounce?.cancel();
    _saveTaskId = taskId;
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _saveDebounce = null;
      final id = _saveTaskId;
      if (id == null) return;
      _saveTaskId = null;
      ReferenceStore.save(id, state.references);
    });
  }

  // ── public API (existing semantics) ─────────────────
  Future<void> load(String taskId) async { ... }      // unchanged

  Future<void> saveAllConfirmed(String taskId) async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _saveTaskId = null;
    await ReferenceStore.save(taskId, state.references);
  }

  void editCheckpoint(int qNum, String cpId, {String? description, int? points}) {
    state = state.copyWith(references: _mapRef(qNum, (r) => r.copyWith(checkpoints: ...)));
    _scheduleSave(/* last known taskId — see 2.2.1 */);
  }
  // ...addCheckpoint / removeCheckpoint / sendMessage / confirm / unconfirm all call _scheduleSave

  // ── in-flight token guard (G4c / S-9) ─────────────
  Future<void> sendMessage(String taskId, int qNum, String msg) async {
    final myToken = _token;
    state = state.copyWith(refining: true, refiningQuestion: qNum);
    try {
      final updated = await _newQwen().refineStrategy(...);
      if (myToken != _token) return;      // disposed mid-flight
      state = state.copyWith(references: ..., refining: false);
    } catch (e) { ... }
    _scheduleSave(taskId);
  }
}
```

#### 2.2.1 Task ID tracking

`_scheduleSave` needs to know the taskId. We add a private `_activeTaskId` field set on `load(taskId)`, then `editCheckpoint` / `addCheckpoint` / etc. read it. This avoids passing `taskId` to every mutator (preserves current API).

#### 2.2.2 App-lifecycle flush (R4 mitigation)

**New**: A `WidgetsBindingObserver` registered in `main.dart` (or a new `app_lifecycle_observer.dart`) listens for `AppLifecycleState.paused` and `AppLifecycleState.detached` and:

- Calls `ref.read(strategyProvider.notifier).flushPendingSave()` which cancels the debounce and immediately persists.
- Calls `ref.read(taskProvider.notifier)._persist()` to ensure latest tasks.json is on disk.

This eliminates the 500ms-loss window for the most common case (teacher puts app in background).

`StrategyNotifier.flushPendingSave()`:

```dart
void flushPendingSave() {
  _saveDebounce?.cancel();
  _saveDebounce = null;
  final id = _saveTaskId;
  _saveTaskId = null;
  if (id == null) return;
  // Fire-and-forget: app is pausing, no caller can await us
  ReferenceStore.save(id, state.references);
}
```

---

## 3. Test Plan

### 3.1 New test files

| File | Cases | Covers |
|---|---|---|
| `test/capture_screen_test.dart` | 1 | G1: confirm dialog on re-upload |
| `test/atomic_io_test.dart` (additions) | 2 | G2: per-item quarantine + atomic rewrite |
| `test/checkpoint_test.dart` (new) | 2 | G3: `CheckpointDef.fromJson` tolerates missing description/points |
| `test/strategy_message_test.dart` (new) | 1 | G3: `StrategyMessage.fromJson` tolerates missing role/content |
| `test/image_compressor_test.dart` (additions) | 1 | G3c: `_inflight` size after N compressed |
| `test/strategy_provider_test.dart` (rewrite) | 8 | G4a-d: non-autoDispose, debounce 5→1 write, all 5 mutators schedule save, in-flight token guard, dispose flushes nothing, flushPendingSave |
| `test/qwen_service_test.dart` (additions) | 1 | G5: clamp 0/maxPoints |
| `test/job_queue_test.dart` (additions) | 1 | G6: cancel → phase=failed |
| `test/submission_test.dart` (new) | 1 | G8: tri-state copyWith clear |
| `test/task_detail_screen_test.dart` (new) | 1 | G9: dialog debounce |
| `test/qwen_error_test.dart` (additions) | 1 | G10: badResponse is non-retryable |

**Total**: 20 new test cases.

### 3.2 TDD ordering within each commit

1. Write the failing test (red)
2. Run `flutter test test/<file>` → see red
3. Write the minimum code to make it pass (green)
4. Run `flutter test` (full suite) → confirm 326+N green
5. Run `flutter analyze` → still 1 info
6. Commit

### 3.3 E2E manual verification (last day)

Run `flutter run -d macos`, then:
- Create a task with 1 question paper photo + 1 student answer photo
- Generate strategy → confirm 1 question → close review → reopen → still confirmed
- Edit a checkpoint → wait 500ms → force-quit app → relaunch → edit present
- Edit a checkpoint → home button (app pause) → relaunch → edit present
- Trigger 2-3 Dio errors (bad API key) → confirm "已取消" state visible
- Open /debug → confirm "Per-item quarantine" section shows 0 quarantined

---

## 4. Doc updates (c12)

### 4.1 CLAUDE.md changes

| Section | Change |
|---|---|
| "Async background jobs" → "Persistence isolation" | Add: "Strategy state is per-session (not autoDispose) so review-screen edits survive navigation; debounced writes (`StrategyNotifier._scheduleSave`, 500ms) persist edits as the user types. `saveAllConfirmed` flushes the debounce." |
| "Data persistence" → "tasks.json" paragraph | Replace "Writes are serialized (see 'Async background jobs' — parallel jobs sharing the same store must go through a mutex)" with: "Reads use **per-item quarantine**: one bad record ≠ whole file lost. Writes are serialized via `TaskNotifier._persistChain`." |
| "Key patterns" → "GradedItem / checkpoint" | Add: "GradedItem.copyWith uses a tri-state `_keep` sentinel so callers can distinguish 'no change' from 'clear teacher override'." |
| "Error handling" → QwenError | Add `QwenErrorKind.badResponse` to the kind list; note it's non-retryable. |

### 4.2 No README changes

README is user-facing Chinese; the 14 bug fixes are all teacher-transparent (no new UI/UX to document).

---

## 5. Risks & Mitigations

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | G4 rewrite introduces new race in debounce + in-flight token | M | M | 8 tests in `strategy_provider_test.dart`; run E2E |
| R2 | G2 per-item quarantine masks serious schema errors | L | M | `.broken` count exposed in `/debug`; c0 audit log makes the policy change findable |
| R3 | CLAUDE.md grep for "mutex" no longer matches | L | L | c12 commit message points to the new line |
| R4 | 500ms debounce loses edit if app crashes between edit + debounce fire | M | L | AppLifecycleState.paused observer flushes immediately (2.2.2) |
| R5 | c0 commit's audit log path is fragile (relative path to ../docs/) | L | L | Use absolute repo-rooted path: `docs/audits/2026-06-05-bug-report-review.md` |

---

## 6. Schedule (2.5 working days)

| Day | Commits | Hours |
|---|---|---|
| Day 1 AM | c0, c1 | 1.5 |
| Day 1 PM | c2 | 3 |
| Day 2 AM | c3 | 2 |
| Day 2 PM | c4a, c4b | 3 |
| Day 3 AM | c4c, c4d | 3 |
| Day 3 PM | c5, c6, c7 | 2 |
| Day 4 AM | c8, c9, c10, c11 | 3 |
| Day 4 PM | c12, E2E | 2 |
| **Total** | **13 commits** | **~20h** |

---

## 7. Acceptance Criteria

- [ ] 13 commits, each referencing `bbbbbiiiigBugs.md#<id>` in the message body
- [ ] `flutter test` shows 326 + 20 = 346 passing, 0 failing
- [ ] `flutter analyze` shows ≤ 1 info
- [ ] `flutter run -d macos` + manual E2E flow passes
- [ ] `docs/audits/2026-06-05-bug-report-review.md` exists and lists all 6 WRONG + 14 partial claims with evidence
- [ ] CLAUDE.md updated per section 4.1
- [ ] No README changes (user-facing text unchanged)

---

## 8. Out of Scope (deferred to future work)

- ⚠️ Partially CONFIRMED claims (14): C-6a, C-6b, C-8, S-3, U-5, U-10, U-12, U-14, U-19, D-4, A-3 — these are real but less severe; not fixed in this round
- ❌ WRONG claims (6): C-6a, C-8, S-3, S-11, D-4, U-19 (the ones in 0+1 level) — documented in c0, not fixed
- All 2-level UX bugs (U-1 through U-20 minus U-15) — future work
- All 2-level doc bugs (D-1, D-2, D-3, D-5, D-6, D-7, D-8, D-9, D-10) except those touched by c12
- 3-level architectural bugs (A-2, A-4) — future work; A-1's "strategyProvider" piece is fixed in c4d
