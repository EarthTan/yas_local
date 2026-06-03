# Strategy Review Screen — L2 Redesign

- **Date:** 2026-06-04
- **Scope:** v1 of an L2-scope UI/UX redesign for `lib/screens/strategy_review_screen.dart`
- **Driver:** BD / demo readiness for K-12 teachers (主科 + 高中/初中, 40–60 students/class)
- **Hero moment:** the strategy review screen is the differentiated "wow" — checkpoint-based rubric the teacher can refine before batch grading
- **Platform priority:** iPhone (primary); same code renders on macOS desktop / iPad

## Context

The current `strategy_review_screen.dart` is a 472-line single-list view: every question is a `_QuestionCard` stacked in a `ListView.builder`. The teacher scrolls, reads AI-generated checkpoints, optionally opens a chat, and taps confirm per question. The first error in the sequential `for` loop's generation is captured but not surfaced inline; AI reasoning is hidden by default; there is no inline edit of a checkpoint (every tweak is a chat round-trip through the LLM); on a phone the action target is small, navigation is scroll-only, and there is no progress visualisation at the top.

We want a screen that lets a teacher on a phone complete Phase 1 review of all rubric items in one session, feels efficient, and looks premium enough to show in a BD recording. The differentiated feature must be the centrepiece, not a hidden tab.

## Goals

1. A teacher on iPhone can review and confirm a 12-question rubric in roughly five minutes using one hand.
2. The teacher can edit any checkpoint (description / points / add / remove) without round-tripping through the LLM.
3. The screen reads as "the AI understood my rubric" — AI reasoning is one tap away, not buried.
4. Existing chat refinement and the existing persistence-on-「完成」 flow are preserved.

## Non-goals (explicit out of v1)

- **L3 auto-save** — `ReferenceStore` is still written only when the teacher taps 完成. Edits live in memory and are persisted on the existing path.
- **L4 desktop polish** — no responsive two-pane layout, no keyboard shortcuts, no macOS sidebar. PageView works on macOS by default and that is enough.
- **Markdown / rich rendering in chat** — chat messages stay plain text, same as today.
- **Question-jump dropdown for > 30 items** — only N ≤ 30 progress dots render; otherwise a simple `X/N` text replaces the dot row.
- **i18n / l10n** — UI copy remains Chinese-only.
- **Dark-mode polish beyond Material defaults** — no custom theme tokens.
- **Re-running AI on a single question's reasoning** — single-question retry regenerates checkpoints only, not reasoning.

## Decisions log

| Decision | Choice | Reasoning |
|---|---|---|
| Direction | UI/UX (deep-dive) | User-requested |
| Hero screen | Strategy review | Most differentiated value of the product |
| Target feel | "我能干完" (efficiency, IDE-like) | For BD, a teacher who can finish quickly is the proof point |
| Platform priority | iPhone | Where teachers actually run the demo; macOS gets the same code for free |
| Layout model | One question per screen, horizontal PageView | Best fit for iPhone thumb-reach + 12–30 question lists |
| Edit interaction | Modal bottom sheet (`showModalBottomSheet`) | iOS-native, predictable, fastest to build |
| Chat refinement | Foldable section in body, badge on toggle | Preserve current behaviour, relocated into `QuestionBody` |
| Persistence | Unchanged (write on 完成 only) | v1 keeps existing reference-store contract |
| Checkpoint identity | `id` field added to `CheckpointDef` | Stable add / edit / remove; old JSONs backfilled on load |
| Retry state | Reuse `refining` / `refiningQuestion` for both chat and single-question retry | Visually identical spinner; avoids extra state |

## Design overview

### Top of screen

```
← 批改策略  · 5/12                       [全部确认]
─────────────────────────────────────────────────
第 5 题 · 主观题                            8 分
● ● ● ◐ ○ ○ ○ ○ ○ ○ ○ ○      (12 进度点, 1=已确认 3=当前 0=未)
```

- `AppBar` title = "批改策略  ·  X/N"; 右上「全部确认」仅当至少 1 题未确认时显示。
- `QuestionHeaderStrip` shows question number, type chip (客观 / 主观), max points.
- Sum of all checkpoint points for this question is computed live; if `sum != maxPoints`, an orange hint "总分 = X，请确认是否需要调整" appears (non-blocking).
- Progress dots: solid green for confirmed, ringed for unconfirmed, red × for failed generation. Tap → `PageController.animateToPage(i, 250ms, easeOutCubic)`.
- Beyond 30 questions, dots collapse to text `X / N` plus a dropdown — out of v1, but the data structure supports it.

### Middle of screen — `QuestionBody` (scrollable)

1. **Checkpoints** — list of cards, each with description, points badge, and an `[编辑]` action. Tap → opens `EditCheckpointSheet`. Empty state shows the existing "暂无批改策略" hint plus a "添加得分点" outlined button.
2. **+ 添加得分点** — outlined button at bottom of list.
3. **▸ 查看 AI 思考过程** — collapsed by default. Tap expands the reasoning text in a grey panel.
4. **▸ 修改策略（对话） [N]** — collapsed by default. Tap expands the chat foldable: scrollable history (max height 200), input row with send button, "AI 回复中…" indicator when `refining && refiningQuestion == qn`. Message count badge = `chatHistory.length ~/ 2`.

### Bottom of screen — `BottomActionBar` (sticky)

```
┌────────────────────────────────────────────────┐
│  [ 修改策略 ]   [ 确认此题 ]   [ 下一题 → ]     │
└────────────────────────────────────────────────┘
```

- `[修改策略]` — toggles chat foldable. Disabled while refining.
- `[确认此题]` — primary action. Solid green if not confirmed → `confirmQuestion(qn)` + `HapticFeedback.lightImpact` + auto-advance to next unconfirmed (or stay if none). Action chip "✓ 已确认" if already confirmed → `unconfirmQuestion(qn)`, no auto-advance.
- `[下一题 →]` — always available. `controller.nextPage(...)`. Disabled at the last page with text "已是最后一题".

### Bottom sheet — `EditCheckpointSheet`

```
┌─────────────────────────────────────┐
│  ━━━                                │  drag handle
│  编辑 checkpoint               [×]  │
│ ──────────────────────────────────  │
│  描述                                │
│  ┌──────────────────────────────┐  │
│  │                              │  │  multiline, 3 lines min
│  └──────────────────────────────┘  │
│                                     │
│  分值                                │
│  [ - ]   3   [ + ]                  │  stepper 1–99
│                                     │
│  ⚠️  全部 checkpoint 分值合计 = 7    │  live, orange if ≠ max
│                                     │
│ ──────────────────────────────────  │
│ [ 删除 ]              [ 取消 ][ 保存 ]│
└─────────────────────────────────────┘
```

- `isScrollControlled: true`, sheet sizes to content (no fixed height).
- `description` empty or `points` out of [1, 99] → save disabled + red hint.
- 删除 button only on edit (not add); confirm via one tap, no extra dialog.
- Cancel or outside-tap dismisses without writing to state.
- `+ 添加得分点` reuses the same widget with title "添加得分点", no delete button, empty initial fields.

### Failed-generation state

- A question whose generation produced `checkpoints.isEmpty` shows a red error bar at the top of the body: "该题生成失败" with a `[重试此题]` button.
- `重试此题` calls `retryGenerate(qn)` which re-runs `QwenService.generateStrategy` for that rubric item only and merges the result into state.

## Data model

### `lib/models/checkpoint.dart`

Add `id` to `CheckpointDef`:

```dart
class CheckpointDef {
  final String id;          // empty string if absent in raw JSON
  final String description;
  final int points;

  const CheckpointDef({
    required this.id,
    required this.description,
    required this.points,
  });

  CheckpointDef copyWith({String? id, String? description, int? points});
  factory CheckpointDef.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

- `fromJson` reads the JSON as-is. If `id` is missing or empty, the resulting `CheckpointDef` has `id == ''`. Backfill of empty ids is the responsibility of `ReferenceAnswer.fromJson` (it knows the question number and the index).
- `toJson` always writes `id`, even when empty (so round-tripping is total). For the common case where the upstream code has already backfilled, this is the original id; for an unbackfilled record, the empty string is preserved through a round-trip and then backfilled on the next `ReferenceAnswer.fromJson`.
- `ReferenceAnswer.checkpoints: List<CheckpointDef>` unchanged.

### `lib/models/reference_answer.dart`

`fromJson` backfills empty checkpoint ids during construction. The wrapped `ReferenceAnswer` returned to callers is always id-bearing:

```dart
factory ReferenceAnswer.fromJson(Map<String, dynamic> json) {
  final qn = json['questionNumber'] as int;
  final rawCheckpoints = (json['checkpoints'] as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map(CheckpointDef.fromJson)
      .toList();
  final checkpoints = [
    for (var i = 0; i < rawCheckpoints.length; i++)
      rawCheckpoints[i].id.isEmpty
          ? rawCheckpoints[i].copyWith(id: 'q$qn-cp$i')
          : rawCheckpoints[i],
  ];
  return ReferenceAnswer(
    questionNumber: qn,
    checkpoints: checkpoints,
    hasConsensus: json['hasConsensus'] as bool? ?? true,
    reasoning: json['reasoning'] as String?,
    chatHistory: ((json['chatHistory'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(StrategyMessage.fromJson)
        .toList(),
    confirmed: json['confirmed'] as bool? ?? false,
  );
}
```

### `lib/services/reference_store.dart`

No code change beyond the existing `load` / `save` path — id backfill is now owned by `ReferenceAnswer.fromJson`, which is invoked from `ReferenceStore.load` exactly as before. In-memory state is always id-bearing. The first save after this upgrade rewrites the file with ids.

## Provider changes

### `lib/providers/strategy_provider.dart`

New methods on `StrategyNotifier`:

```dart
void editCheckpoint(int questionNumber, String checkpointId, {String? description, int? points});
void addCheckpoint(int questionNumber, {required String description, required int points});
void removeCheckpoint(int questionNumber, String checkpointId);
Future<void> retryGenerate(int questionNumber);
```

Implementation notes:

- All three synchronous mutators locate the `ReferenceAnswer` by `questionNumber`, then locate the checkpoint by `id`. They rebuild `state.references` and emit `state.copyWith(references: newRefs)`.
- New checkpoint `id` in `addCheckpoint` is generated as `DateTime.now().microsecondsSinceEpoch.toString()` — unique within a session and stable across save/load.
- `retryGenerate(qn)`:
  1. Set `refining: true, refiningQuestion: qn`.
  2. Call `QwenService.generateStrategy(rubricItem, ...)`.
  3. On success: replace that question's entry in `state.references`, clear refining. (The returned `ReferenceAnswer.checkpoints` is already id-bearing because `QwenService` parses via `ReferenceAnswer.fromJson`.)
  4. On error: keep `checkpoints` empty for that question, set `state.error`, clear refining.
- Each operation records a `DebugService.instance.recordEvent` (consistent with the recently-added debug instrumentation).
- `refining` / `refiningQuestion` semantics are extended to "AI in flight for this question (chat or single-question retry)". Visually identical spinner; this avoids new state.
- `StrategyState` field set is unchanged.

## File plan

| Action | Path | Reason |
|---|---|---|
| Modify | `lib/models/checkpoint.dart` | Add `id` to `CheckpointDef` |
| Modify | `lib/services/reference_store.dart` | No code change; backfill owned by `ReferenceAnswer.fromJson` (called from existing `load` path) |
| Modify | `lib/providers/strategy_provider.dart` | Add 4 new methods (`editCheckpoint`, `addCheckpoint`, `removeCheckpoint`, `retryGenerate`) |
| Modify | `lib/screens/strategy_review_screen.dart` | Replace body with PageView + new components |
| Add | `lib/screens/strategy_review/question_page.dart` | New: one question per page widget |
| Add | `lib/screens/strategy_review/edit_checkpoint_sheet.dart` | New: modal bottom sheet editor |
| Add | `lib/screens/strategy_review/progress_dots.dart` | New: top progress dots widget |
| Add | `lib/screens/strategy_review/bottom_action_bar.dart` | New: sticky action bar widget |
| Add | `test/strategy_screen_test.dart` | New: widget tests for the redesign |
| Modify | `test/json_extractor_test.dart` | Unchanged content; left as-is |
| Modify | `test/grading_test.dart` | Add round-trip for `CheckpointDef` with id |

The single file `strategy_review_screen.dart` is split into a small folder because the design now has four cohesive components; each file is ≤ 200 lines and has a single purpose. Reusing the current folder pattern (or not) is an implementation choice — leaving flexibility for the implementer.

## Data flow

1. `StrategyReviewScreen.initState` → `loadOrGenerate(taskId)` (unchanged).
2. `loadOrGenerate` calls `ReferenceStore.load(taskId)` → `ReferenceAnswer.fromJson` (invoked from inside `load`) backfills empty ids → returns id-bearing list.
3. If cache miss, `_generate` runs sequentially. For each item, the returned `ReferenceAnswer` is already id-bearing (parsed via the same `fromJson` path), and is added to state.
4. `PageView` reads `state.references`; each page is a `QuestionPage(qn, reference, ...)`.
5. Tap checkpoint → `showModalBottomSheet` with `EditCheckpointSheet(reference, checkpointId)`.
6. Save → calls `notifier.editCheckpoint(qn, id, description: ..., points: ...)` → state updated → widget rebuilds.
7. Add → `notifier.addCheckpoint(qn, ...)` → state updated.
8. Remove → `notifier.removeCheckpoint(qn, id)` → state updated.
9. Tap "确认" → `notifier.confirmQuestion(qn)` → state updated → `controller.animateToPage(nextUnconfirmedIndex, ...)`.
10. Tap "全部确认" → existing `notifier.confirmAll()` (unchanged).
11. Tap "完成" (bottom, enabled only when `allConfirmed`) → existing `notifier.saveAllConfirmed(taskId)` → `pushReplacement('/tasks/:id')`.

## Error handling

| Failure | Behaviour |
|---|---|
| Edit sheet: empty description or points out of range | Save disabled + red hint under field; no dialog |
| Edit sheet: outside-tap or cancel | Sheet closes, state untouched |
| Add checkpoint: same validation as edit | Same as edit |
| Remove checkpoint: confirmed via one tap | No extra confirm dialog (iOS pattern) |
| Single-question retry: API error | `state.error` set with `ErrorFormatter.format(e)`; checkpoint list stays empty; red error bar shown |
| First-error-during-initial-generation: same as today | Captured into `state.error`, surfaced in the existing error view |
| Network / Qwen 4xx / 5xx | Standard `ErrorFormatter` Chinese message, identical to current behaviour |
| Sheet rendered while a generation retry is in flight | Block: `addCheckpoint` / `editCheckpoint` / `removeCheckpoint` no-op until `refining == false` |

## Testing plan

Add `test/strategy_screen_test.dart` and one test in `test/grading_test.dart`:

| Test | Validates |
|---|---|
| `CheckpointDef.fromJson leaves id empty when missing` | Given `{description, points}` without id, `fromJson` returns id == `''` |
| `CheckpointDef.toJson always writes id` | After toJson, the map contains the `id` field |
| `ReferenceAnswer.fromJson backfills empty checkpoint ids` | Construct from JSON with empty ids, all checkpoints in result have non-empty id == `qN-cpI` |
| `StrategyNotifier editCheckpoint replaces by id` | Edit one of three checkpoints; the others untouched by id |
| `StrategyNotifier addCheckpoint appends with new id` | After add, list length +1, last item id is non-empty and unique |
| `StrategyNotifier removeCheckpoint drops by id` | After remove, list length -1, the right one gone |
| `StrategyNotifier retryGenerate replaces that question's state` | Mock QwenService; first call fails (empty checkpoints), retryGenerate succeeds, checkpoint list non-empty |
| `StrategyScreen renders PageView with N pages` | `find.byType(PageView)` exists; `tester.pageController(initialPage: 0).hasClients`; can swipe to last page |
| `Tap checkpoint opens EditCheckpointSheet` | `showModalBottomSheet` invoked; sheet content shows description + points |
| `Edit sheet save updates state and closes` | Save → state contains the new description, sheet closed |
| `Add sheet from "添加得分点" appends checkpoint` | After save, list length +1 |
| `Confirm button advances to next unconfirmed` | Tap confirm on page 0 → `PageController.page == nextUnconfirmedIndex` |
| `Tap progress dot jumps to that index` | Tap dot 5 → page becomes 5 within 500 ms (animation) |
| `Failed-question retry replaces state` | A question with `checkpoints.isEmpty` shows red bar; tap retry → state populates, red bar gone |

## Migration / compatibility

- Existing `reference_<taskId>.json` files written before this change do not contain `id`. `ReferenceStore.load` backfills on read. The first time the teacher taps 完成, the file is rewritten with ids. No user action required; no data loss.
- A `ReferenceAnswer.checkpoints` of length 0 still works — backfill is a no-op.
- The on-disk JSON shape gains one field (`id` on each `CheckpointDef`). This is forward-compatible: an older app reading a newer file would see unknown `id` and ignore it (current `fromJson` only reads known fields).

## Open questions / risks

- **Auto-save is intentionally out of scope** but a teacher who edits a checkpoint and force-quits the app will lose those edits. If BD feedback shows this is a frequent pain, L3 is the next increment.
- **"Next unconfirmed" auto-advance** assumes the teacher wants to skip confirmed questions. If teacher feedback says they want to revisit already-confirmed questions, the action can be re-bound to "next page" instead.
- **PageView + bottom sheet** in iOS sometimes fights with the keyboard. We will use `isScrollControlled: true` and verify keyboard behaviour in a manual smoke test on iPhone simulator before declaring done.
- **iPad / macOS rendering** is unverified beyond the default `showModalBottomSheet` behaviour. If layout looks broken on a wide canvas, the response is to constrain max width (e.g., wrap in a `Center` + `ConstrainedBox(maxWidth: 600)`) — but that polish is not in v1.
- **No dark-mode custom tokens**: Material 3 default dark theme will be used. Visual polish on dark mode is a L4 concern.
