# Navigation Stack Duplication Fix

Date: 2026-06-07
Status: Draft

## Problem

After completing work in a sub-screen (strategy review, capture, create flow), the back stack contains two instances of the task detail route. Pressing the system Back button or the AppBar back button pops the topmost task detail and reveals the previous one — the user feels they're "returning to task detail again" instead of going home. Repeated presses are needed to actually leave the task.

### Root cause

`GoRouter.pushReplacement` is documented as "Replaces the top-most page of the page stack" ([go_router docs](https://pub.dev/documentation/go_router/latest/go_router/GoRouterHelper/pushReplacement.html)). It does NOT deduplicate. When the target route is already present in the stack, `pushReplacement` pushes a new instance of that route on top of the existing one.

Concrete trace from the recorded session (testet task, math rubric, 9 questions all confirmed):

```
1. [/]                                  home
2. push  /tasks/A          →  [/, /tasks/A]
3. push  /tasks/A/strategy →  [/, /tasks/A, /tasks/A/strategy]
4. pushReplacement /tasks/A →  [/, /tasks/A, /tasks/A]    ← duplicate
5. system Back                  →  pop top /tasks/A     →  [/, /tasks/A]
                                  (user sees "another task detail")
6. system Back                  →  pop /tasks/A         →  [/]  (home)
```

User intent in step 4 is "drop the strategy sub-screen, I'm back on the task detail." Actual behavior: a new task-detail instance is layered on top of the existing one.

## Affected call sites

Two locations use `context.pushReplacement` to navigate to a route that is already present lower in the stack:

| File | Line | From | To | In stack? |
|---|---|---|---|---|
| `lib/screens/strategy_review_screen.dart` | 341 | `/tasks/:id/strategy` (完成按钮) | `/tasks/:id` | yes — bug |
| `lib/screens/capture_screen.dart` | 98 | `/tasks/:id/capture` (上传完成) | `/tasks/:id` | yes — bug |
| `lib/screens/create_task_screen.dart` | 140 | `/tasks/create` (创建完成) | `/tasks/:id/identify` | no — not a bug |

`strategy_review_screen.dart:341` is the call site demonstrated in the bug report.

`capture_screen.dart:98` has the same latent bug — stack is `[/, /tasks/:id, /tasks/:id/capture]` when capture completes, and `/tasks/:id` is already in the stack. Fixed in the same pass.

`create_task_screen.dart:140` is **not** affected: the stack at that point is `[/, /tasks/create]`, and the target `/tasks/:id/identify` is not in the stack, so `pushReplacement` behaves correctly as a replace. Left untouched.

## Fix

Replace `context.pushReplacement(<route>)` with `context.go(<route>)` at all three call sites.

`go()` navigates to the location, matching an existing instance of the route in the stack and re-using it rather than pushing a duplicate. Stack after the fix:

```
4. go /tasks/A  →  [/, /tasks/A]    ← single instance, system Back goes straight to home
```

### Why `go()` and not "manual pop + pushReplacement"

- `go()` expresses the intent: "navigate to the task detail" (the route is a known location, not a new layer).
- Manual pop requires knowing the current stack depth and is fragile if the user navigated non-linearly (e.g. deep link into strategy review).
- `pushReplacement` is the wrong primitive for "navigate to a known location" — it's for "replace top with this other route," which is what we want only when the target is NOT already in the stack.

### Animation note

`go()` and `pushReplacement` use the same default page transition (`MaterialPage` / `CupertinoPage`). The user-visible animation in both cases is "current page slides off, new page slides in." No animation regression is introduced.

## Files to change

- `lib/screens/strategy_review_screen.dart` — line 341
- `lib/screens/capture_screen.dart` — line 98

`lib/screens/create_task_screen.dart:140` is intentionally NOT changed (target not in stack).

No other code or routing config changes required.

## Tests

Add a single integration-style test that asserts the post-`完成` stack contains exactly one instance of `/tasks/:id`.

The simplest test path is unit-level: drive the strategy review screen's `完成` button in a widget test, then assert `GoRouter.routerDelegate.currentConfiguration.matches.length` is the expected count.

If widget tests are too heavy for the existing harness (most existing tests are pure-Dart per CLAUDE.md), fall back to a small helper that wraps the navigation and a unit test on the helper. Decide during plan-writing.

## Out of scope

- The "animation direction" concern the user mentioned (sub-pages should slide out to the right, not push a new task detail in from the right). This is a separate UX issue and would require a child-navigator architecture. Not addressed here.
- Adding a quick-jump-to-task-detail button. Not needed once the stack duplication is gone.
- Other `context.push` call sites (task detail → identify, task detail → strategy review pre-completion, task detail → results, task detail → capture, results → paper detail, home → settings, home → create task). These push to a route that is NOT already in the stack, so the duplication bug does not apply.
