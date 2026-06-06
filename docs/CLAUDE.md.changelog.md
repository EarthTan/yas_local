# CLAUDE.md Sync Changelog (2026-06-06)

> **Why this file exists:** the YAS project's `CLAUDE.md` is at the
> parent workspace root (`../CLAUDE.md` from `yas_local/`), which is
> outside the Flutter project's git working tree. The c12 step of the
> 2026-06-05 selective bug-fix plan called for editing it in place, but
> the file is not tracked by the `yas_local/` git repo, so the edit
> is best left as a hand-applied patch by a human reviewer.
>
> **To apply:** open `../CLAUDE.md`, find each section marked with a
> `←` arrow below, and apply the diff. The arrows mark the *current*
> text in the file; replace each with the `→ replacement` text.

## 1. `JobState` description (section "Async background jobs", first bullet)

← `There is no `cancelled` phase; a cancelled job ends as `done` with fewer units processed.`

→ `There is no `cancelled` phase; a cancelled job ends as `failed` with `error: '用户已取消'` and fewer units processed.`

## 2. `Persistence isolation` bullet

← ```text
- **Persistence isolation**: jobs themselves are session-scoped (not written to disk). Durable progress lives on each `Submission`'s status; durable strategy output lives in `reference_<taskId>.json`. `TaskStore` writes are serialized via a mutex so parallel jobs persisting to `tasks.json` don't clobber each other.
```

→ ```text
- **Persistence isolation**: jobs themselves are session-scoped (not written to disk). Durable progress lives on each `Submission`'s status; durable strategy output lives in `reference_<taskId>.json`. `TaskStore` reads use **per-item quarantine**: one bad record ≠ whole file lost; the bad record is renamed aside (the `.broken.<type>.<micros>.<counter>` file is visible in `/debug`) and the surviving records are atomically re-written. `TaskStore` writes are serialized via a mutex (see `TaskNotifier._persistChain` in `task_provider.dart:42-58`) so parallel jobs persisting to `tasks.json` don't clobber each other.
```

## 3. `Image preprocessing` bullet

← `- **Image preprocessing**: every image handed to Qwen goes through `ImageCompressor` first (longest edge ≤ 1600px JPEG, cached on disk, deduped in-flight). Treat it as transparent — never re-introduce a path that bypasses it.`

→ `- **Image preprocessing**: every image handed to Qwen goes through `ImageCompressor` first (longest edge forced to 1600px JPEG — smaller images are upscaled, larger ones downscaled; cached on disk; deduped in-flight; `_inflight` map is cleaned up on `whenComplete`). Treat it as transparent — never re-introduce a path that bypasses it.`

## 4. `Interactive strategy refinement` bullet

← `- **Interactive strategy refinement**: `ReferenceAnswer.confirmed` + `chatHistory` enable a teacher-in-the-loop workflow where strategy can be iterated per-question before final grading. Refinement (`refineStrategy`) is a *sync* call from the review screen, distinct from the *async* generation done by `JobQueueNotifier.startStrategy`.`

→ `- **Interactive strategy refinement**: `ReferenceAnswer.confirmed` + `chatHistory` enable a teacher-in-the-loop workflow where strategy can be iterated per-question before final grading. Refinement (`refineStrategy`) is a *sync* call from the review screen, distinct from the *async* generation done by `JobQueueNotifier.startStrategy`. `strategyProvider` is **not** autoDispose; the notifier survives navigation, and edits are debounced (500ms) via `StrategyNotifier._scheduleSave` to `reference_<taskId>.json`. `saveAllConfirmed` flushes the debounce. The `AppLifecycleObserver` in `lib/services/` calls `flushPendingSave` on `paused`/`detached` so the debounce window is not a data-loss risk.`

## 5. `Error handling` bullet

← `- **Error handling**: `lib/services/error_formatter.dart` formats Dio errors in Chinese with URL, status code, and response snippet. First error in a batch is surfaced on the job's `error` field; the batch continues.`

→ `- **Error handling**: `lib/services/error_formatter.dart` formats Dio errors in Chinese with URL, status code, and response snippet. `QwenErrorKind` covers `network` / `timeout` / `http4xx` / `http5xx` / `badResponse` / `jsonParse` / `unknown`; `http4xx` and `badResponse` are non-retryable (config/auth problems and malformed-body 5xx respectively, neither worth retrying). First error in a batch is surfaced on the job's `error` field; the batch continues.`

## 6. `Teacher overrides` bullet (optional — c8 doesn't have UI yet, but the API is shipped)

← `- **Teacher overrides**: `GradedItem.finalScore` prefers `teacherScore` over `aiScore`; `teacherScore` set via slider in `paper_detail_screen.dart`.`

→ `- **Teacher overrides**: `GradedItem.finalScore` prefers `teacherScore` over `aiScore`; `teacherScore` set via slider in `paper_detail_screen.dart`. `GradedItem.copyWith` uses a tri-state `clearTeacherScore: true` parameter to distinguish "no change" from "clear to null" (no UI for clearing yet — paper_detail_screen still only sets via the slider).`

---

## Bugs fixed in this round (cross-reference)

| Bug | Fix commit | Type |
|---|---|---|
| C-1 | c336fdb (rename) + 8647983 (test) | data loss — silent delete on second capture |
| C-2 | 11397a1 | data loss — bad record quarantined whole file |
| C-3 | 19f01f2 | data loss — `CheckpointDef.fromJson` throw |
| C-4 | 33db26e | data loss — editCheckpoint not persisted |
| C-5 | 6c21c62 | data loss — chat history not persisted |
| C-9 | 19f01f2 | memory leak — ImageCompressor._inflight |
| S-4 | 6208bf3 | state — LLM negative/over-max scores |
| S-5 | 590f7ad | state — cancelled job shown as 完成 |
| S-6 | a043a78 | state — type erasure on grades |
| S-7 | dc3b87a | state — copyWith(null) cannot clear |
| S-8 | ea28911 | state — regrade dialog not debounced |
| S-9 | af319e7 | state — used-after-dispose on in-flight |
| S-10 | 19f01f2 | state — StrategyMessage.fromJson throw |
| S-12 | caf0600 | state — badResponse retried 3 times |
| U-15 | 5940a8b | state — identify controller leak |
| A-1 | c482735 | arch — strategyProvider non-autoDispose + lifecycle flush |

All 16 commit trailers reference `bbbbbiiiigBugs.md#<id>`.
