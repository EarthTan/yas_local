# Navigation Stack Duplication Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the navigation stack duplication bug: completing strategy review or capture leaves two instances of `/tasks/:id` in the GoRouter stack, requiring multiple back presses to return home.

**Architecture:** Replace two `context.pushReplacement` calls with `context.go` at the affected sites. `go()` matches an existing route in the stack and reuses it; `pushReplacement` pushes a duplicate when the target is already present in the stack.

**Tech Stack:** Flutter 3.x, GoRouter 13.2.0, Riverpod 2.5.1, widget tests via `flutter_test` with `TestWidgetsFlutterBinding`.

---

## File Structure

| File | Change |
|---|---|
| `lib/screens/strategy_review_screen.dart` | Replace `pushReplacement` with `go` on line 341 |
| `lib/screens/capture_screen.dart` | Replace `pushReplacement` with `go` on line 98 |
| `test/strategy_navigation_test.dart` | Restructure setup to model real stack + add stack-length assertion |

`lib/screens/create_task_screen.dart:140` is intentionally NOT changed (its target route is not in the stack — see spec).

No new files in `lib/`. Two files modified in `lib/`. One test modified.

---

## Task 1: Restructure strategy navigation test to model real stack and assert single task-detail

**Files:**
- Modify: `test/strategy_navigation_test.dart:44-87`

The existing test starts the router at `/tasks/t1/strategy`, which does NOT model the real app flow. In the real app, the user navigates `/` → `/tasks/:id` → `/tasks/:id/strategy`, so the stack at strategy time is `[/tasks/:id, /tasks/:id/strategy]`. With the existing test setup, the stack is just `[/tasks/:id/strategy]` — pushReplacement behaves correctly in that empty-prior case. The test must build the real stack before pressing 完成, otherwise the assertion can't catch the bug.

- [ ] **Step 1: Update the test setup to model the real stack**

In `test/strategy_navigation_test.dart`, change `initialLocation` from `/tasks/t1/strategy` to `/tasks/t1`, then after `pumpWidget` push the strategy route to put the stack into `[/tasks/t1, /tasks/t1/strategy]`. The full new setup:

```dart
      final router = GoRouter(
        initialLocation: '/tasks/t1',
        routes: [
          GoRoute(
            path: '/tasks/:id',
            builder: (_, _) => const Scaffold(body: Text('task-hub')),
          ),
          GoRoute(
            path: '/tasks/:id/strategy',
            builder: (_, s) =>
                StrategyReviewScreen(taskId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/tasks/:id/grading',
            builder: (_, _) => const Scaffold(body: Text('grading-screen')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            strategyProvider.overrideWith((ref) => _AllConfirmedNotifier(ref)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();

      // Walk the router forward to strategy so the stack matches the real
      // app flow: [/tasks/t1] → [/tasks/t1, /tasks/t1/strategy]. Without
      // this push, the stack would be [/tasks/t1] and pushReplacement
      // would behave correctly — the test would not catch the bug.
      router.push('/tasks/t1/strategy');
      await tester.pumpAndSettle();
```

- [ ] **Step 2: Add stack-length assertion after the existing expects**

After the existing `expect(find.text('grading-screen'), findsNothing);` (line 85), add:

```dart
      // The router stack must contain exactly one /tasks/:id entry. Before
      // the fix, pushReplacement pushes a duplicate task-detail on top of
      // the existing one, so the stack has two matches for /tasks/:id.
      final matches = router.routerDelegate.currentConfiguration.matches;
      final taskHubCount = matches
          .where((m) => m.matchedLocation == '/tasks/t1')
          .length;
      expect(taskHubCount, 1,
          reason:
              'GoRouter stack should have exactly one /tasks/:id entry after strategy 完成; '
              'pushReplacement leaves the prior instance in the stack.');
```

- [ ] **Step 3: Run the test to verify it fails on current (buggy) code**

Run: `cd yas_local && flutter test test/strategy_navigation_test.dart`
Expected: FAIL with `Expected: 1, Actual: 2` from the `taskHubCount` assertion. The earlier `find.text('task-hub')` expect still passes (the visible screen is correct) — only the new stack-length assertion fails.

- [ ] **Step 4: Commit the failing test**

```bash
cd yas_local
git add test/strategy_navigation_test.dart
git commit -m "test(strategy): assert single task-detail in stack after 完成"
```

---

## Task 2: Fix strategy_review_screen navigation

**Files:**
- Modify: `lib/screens/strategy_review_screen.dart:341`

- [ ] **Step 1: Replace pushReplacement with go**

In `lib/screens/strategy_review_screen.dart`, the existing line 341 is:

```dart
                          context.pushReplacement('/tasks/${widget.taskId}');
```

Replace it with:

```dart
                          context.go('/tasks/${widget.taskId}');
```

- [ ] **Step 2: Run the strategy navigation test**

Run: `cd yas_local && flutter test test/strategy_navigation_test.dart`
Expected: PASS. The new `taskHubCount` assertion now sees exactly one `/tasks/t1` match.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/screens/strategy_review_screen.dart
git commit -m "fix(nav): use go() to avoid duplicate task-detail in stack"
```

---

## Task 3: Fix capture_screen navigation

**Files:**
- Modify: `lib/screens/capture_screen.dart:98`

- [ ] **Step 1: Replace pushReplacement with go**

In `lib/screens/capture_screen.dart`, the existing line 98 is:

```dart
    context.pushReplacement('/tasks/${widget.taskId}');
```

Replace it with:

```dart
    context.go('/tasks/${widget.taskId}');
```

- [ ] **Step 2: Run the full test suite to confirm no regression**

Run: `cd yas_local && flutter test`
Expected: All tests pass. The strategy_navigation_test (Task 1) continues to pass; capture_screen_test continues to test the `replaceSubmissions` API; no other test exercises the navigation path.

- [ ] **Step 3: Commit**

```bash
cd yas_local
git add lib/screens/capture_screen.dart
git commit -m "fix(nav): use go() in capture screen to avoid duplicate task-detail"
```

---

## Task 4: Manual verification

The capture fix cannot be fully verified by automated tests because driving the capture flow requires a real `image_picker` (a platform plugin) to inject a non-empty photo list, and `capture_screen.dart` keeps `_photos` as private state with no test seam. The strategy fix IS covered by Task 1's widget test. The capture call site is the same one-line `go()` form, so the strategy test exercises the load-bearing semantics.

- [ ] **Step 1: Reproduce the original bug path on the post-fix build**

Run: `cd yas_local && flutter run -d macos`

Strategy flow (covered by Task 1 widget test, but verify in UI):
1. From home, tap a task with confirmed strategy (e.g. testet).
2. Tap "查看/修改批改策略".
3. Tap "完成".
4. Tap the AppBar back arrow (←).

Expected: Returns directly to home, in exactly one back press. (Before fix: returned to a duplicate task-detail; required a second back press to reach home.)

- [ ] **Step 2: Verify the capture flow**

Sequence:
1. From home, tap any task.
2. Tap "上传学生作业".
3. Pick one or more photos, tap "下一步", confirm any overwrite prompt.
4. After upload, tap the AppBar back arrow.

Expected: Returns directly to home in one back press.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| Problem statement (stack duplication) | Task 1 (test), Tasks 2-3 (fix) |
| Affected call sites (strategy_review, capture) | Tasks 2, 3 |
| Files to change | Tasks 2, 3 |
| Tests | Task 1 (strategy); manual for capture (Task 4) |
| Out of scope (animation direction) | not addressed, per spec |

**2. Placeholder scan:** No "TBD" / "TODO" / "fill in later" / placeholder test code in the final plan.

**3. Type consistency:** `context.go` and `context.pushReplacement` are both `GoRouterHelper` extension methods on `BuildContext`, same signature `(String location) → Future<T?>`. No type drift between tasks.

**4. `create_task_screen.dart:140`:** Explicitly excluded in the spec — its target `/tasks/:id/identify` is not in the stack, so `pushReplacement` is correct. The plan does not touch it.
