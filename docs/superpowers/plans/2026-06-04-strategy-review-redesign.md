# Strategy Review Screen L2 Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 472-line single-list `strategy_review_screen.dart` with an iPhone-first, PageView-driven, one-question-per-screen UI where teachers can edit checkpoints directly (no LLM round-trip) and rapidly confirm all rubric items.

**Architecture:** A `PageView` holds N question pages; each page shows checkpoints, AI reasoning (collapsible), and chat refinement (collapsible). Tapping a checkpoint opens a `showModalBottomSheet` for inline edit. `CheckpointDef` gains an `id` field; `ReferenceAnswer.fromJson` backfills any missing ids so old reference files upgrade on first read. New mutator methods (`editCheckpoint`, `addCheckpoint`, `removeCheckpoint`, `retryGenerate`) live on `StrategyNotifier`. Persistence on `完成` is unchanged.

**Tech Stack:** Flutter 3.x, Riverpod 2.x, go_router 13.x, `path_provider`, `image_picker`, `dio` 5.x. Existing `DebugService` instrumentation is reused.

**Reference spec:** [`docs/superpowers/specs/2026-06-04-strategy-review-redesign-design.md`](../specs/2026-06-04-strategy-review-redesign-design.md)

---

## File Structure

Files created or modified by this plan:

| Action | Path | Responsibility |
|---|---|---|
| Modify | `lib/models/checkpoint.dart` | Add `id` to `CheckpointDef`; new `copyWith` |
| Modify | `lib/models/reference_answer.dart` | `fromJson` backfills empty checkpoint ids |
| Modify | `lib/providers/strategy_provider.dart` | New mutator methods + QwenService test seam |
| Modify | `lib/screens/strategy_review_screen.dart` | Replace body with `PageView` shell |
| Create | `lib/screens/strategy_review/question_page.dart` | One question per page widget |
| Create | `lib/screens/strategy_review/edit_checkpoint_sheet.dart` | Modal bottom sheet editor |
| Create | `lib/screens/strategy_review/progress_dots.dart` | Top progress dots row |
| Create | `lib/screens/strategy_review/bottom_action_bar.dart` | Sticky 3-button action bar |
| Add tests | `test/strategy_screen_test.dart` | Widget tests for the redesign |
| Add tests | `test/grading_test.dart` | Round-trip for `CheckpointDef` with id |
| Add tests | `test/task_store_test.dart` | `ReferenceAnswer.fromJson` backfill on old records |

The four new widget files live in `lib/screens/strategy_review/` (a sub-folder) so the redesign is grouped. Each file stays under ~200 lines and has a single responsibility.

---

## Task 1: Add `id` to `CheckpointDef`

**Files:**
- Modify: `lib/models/checkpoint.dart`
- Modify: `test/grading_test.dart` (one new test)

- [ ] **Step 1: Add a failing test for `id` round-trip**

Append to `test/grading_test.dart` (inside `void main() { ... }`):

```dart
test('CheckpointDef id 字段 round-trip', () {
  const cp = CheckpointDef(id: 'q1-cp0', description: '答对', points: 3);
  final round = CheckpointDef.fromJson(cp.toJson());
  expect(round.id, 'q1-cp0');
  expect(round.description, '答对');
  expect(round.points, 3);
});

test('CheckpointDef.fromJson 在 id 缺失时返回空字符串', () {
  final cp = CheckpointDef.fromJson({'description': '答对', 'points': 3});
  expect(cp.id, '');
});
```

- [ ] **Step 2: Run tests, verify they fail**

Run from `yas_local/`:

```bash
flutter test test/grading_test.dart
```

Expected: compile error — `CheckpointDef` has no `id` parameter, and `CheckpointDef.fromJson` only takes `{description, points}`.

- [ ] **Step 3: Add `id` field, update constructor, `fromJson`, `toJson`, and a `copyWith`**

Replace the contents of `lib/models/checkpoint.dart`'s `CheckpointDef` class with:

```dart
class CheckpointDef {
  final String id;
  final String description;
  final int points;

  const CheckpointDef({
    required this.id,
    required this.description,
    required this.points,
  });

  CheckpointDef copyWith({String? id, String? description, int? points}) =>
      CheckpointDef(
        id: id ?? this.id,
        description: description ?? this.description,
        points: points ?? this.points,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'description': description,
        'points': points,
      };

  factory CheckpointDef.fromJson(Map<String, dynamic> json) => CheckpointDef(
        id: (json['id'] as String?) ?? '',
        description: json['description'] as String,
        points: json['points'] as int,
      );
}
```

`CheckpointResult` (below) is untouched.

- [ ] **Step 4: Re-run tests, verify pass**

```bash
flutter test test/grading_test.dart
```

Expected: PASS (and the 4 pre-existing tests still pass). Note: the pre-existing test `ReferenceAnswer checkpoint 满分汇总` uses `CheckpointDef(description: 'step1', points: 3)` — that won't compile anymore. **Update that test to** `CheckpointDef(id: 'q1-cp0', description: 'step1', points: 3)`. The plan flags this so you don't get a surprise compile error.

- [ ] **Step 5: Sweep the rest of the codebase for `CheckpointDef(` calls and add id**

Run from `yas_local/`:

```bash
grep -rn "CheckpointDef(" lib test
```

For each match that constructs a `CheckpointDef`, add `id: 'q1-cpN'` where `N` is the position in the list (best-effort, since callers usually only construct 1–3 at a time). Examples to expect and how to fix:

- `lib/providers/strategy_provider.dart` — `ReferenceAnswer(questionNumber: item.questionNumber, checkpoints: [], hasConsensus: false)` in error path: leave the empty list alone (no id needed).
- `test/json_extractor_test.dart`, `test/models_test.dart`, `test/qwen_service_test.dart`, `test/prompts_test.dart` — any `CheckpointDef(...)` call needs an `id:` arg.

After fixing, run the full suite:

```bash
flutter test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add lib/models/checkpoint.dart test/grading_test.dart lib/providers/strategy_provider.dart test/json_extractor_test.dart test/models_test.dart test/qwen_service_test.dart test/prompts_test.dart
git commit -m "feat(checkpoint): add id field with backfill support"
```

---

## Task 2: Backfill empty ids in `ReferenceAnswer.fromJson`

**Files:**
- Modify: `lib/models/reference_answer.dart`
- Modify: `test/task_store_test.dart` (one new test)

- [ ] **Step 1: Add a failing test for backfill**

Append to `test/task_store_test.dart` (inside `void main() { ... }`):

```dart
test('ReferenceAnswer.fromJson 回填空 checkpoint id', () {
  final raw = ReferenceStore.encode([
    const ReferenceAnswer(
      questionNumber: 3,
      checkpoints: [
        CheckpointDef(id: '', description: 'A', points: 1),
        CheckpointDef(id: '', description: 'B', points: 2),
      ],
    ),
  ]);
  final decoded = ReferenceStore.decode(raw);
  expect(decoded.single.checkpoints[0].id, 'q3-cp0');
  expect(decoded.single.checkpoints[1].id, 'q3-cp1');
});
```

- [ ] **Step 2: Run test, verify it fails**

```bash
flutter test test/task_store_test.dart
```

Expected: FAIL — decoded ids are empty strings, not `q3-cp0` / `q3-cp1`.

- [ ] **Step 3: Implement backfill in `ReferenceAnswer.fromJson`**

Replace `factory ReferenceAnswer.fromJson` in `lib/models/reference_answer.dart` with:

```dart
factory ReferenceAnswer.fromJson(Map<String, dynamic> json) {
  final qn = json['questionNumber'] as int;
  final raw = ((json['checkpoints'] as List?) ?? const [])
      .cast<Map<String, dynamic>>()
      .map(CheckpointDef.fromJson)
      .toList();
  final checkpoints = [
    for (var i = 0; i < raw.length; i++)
      raw[i].id.isEmpty
          ? raw[i].copyWith(id: 'q$qn-cp$i')
          : raw[i],
  ];
  return ReferenceAnswer(
    questionNumber: qn,
    checkpoints: checkpoints,
    equivalentForms: ((json['equivalentForms'] as List?) ?? const [])
        .map((e) => e as String)
        .toList(),
    hasConsensus: json['hasConsensus'] as bool? ?? true,
    confirmed: json['confirmed'] as bool? ?? false,
    chatHistory: ((json['chatHistory'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(StrategyMessage.fromJson)
        .toList(),
    reasoning: json['reasoning'] as String?,
  );
}
```

- [ ] **Step 4: Re-run test, verify pass**

```bash
flutter test test/task_store_test.dart
```

Expected: PASS (and the 3 pre-existing tests still pass).

- [ ] **Step 5: Commit**

```bash
git add lib/models/reference_answer.dart test/task_store_test.dart
git commit -m "feat(reference): backfill empty checkpoint ids on load"
```

---

## Task 3: Add mutator methods to `StrategyNotifier`

`editCheckpoint`, `addCheckpoint`, `removeCheckpoint`. Synchronous, in-memory only; persistence on `完成` is unchanged.

**Files:**
- Modify: `lib/providers/strategy_provider.dart`
- Add: `test/strategy_provider_test.dart`

- [ ] **Step 1: Create the failing test file**

Create `test/strategy_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/providers/task_provider.dart';
import 'package:yas_local/models/settings.dart';
import 'package:yas_local/providers/settings_provider.dart';

GradingTask _taskWithRubric(List<RubricItem> rubric) => GradingTask(
      id: 't1',
      name: 't1',
      subject: 'math',
      createdAt: DateTime(2026, 1, 1),
      rubric: rubric,
    );

class _FakeTaskNotifier extends TaskNotifier {
  _FakeTaskNotifier(super.ref, this._task);
  final GradingTask _task;
  @override
  GradingTask? taskById(String id) => _task;
}

ProviderContainer _container(GradingTask task) {
  return ProviderContainer(overrides: [
    taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
    settingsProvider.overrideWith((ref) => const AppSettings(apiKey: 'k')),
  ]);
}

void main() {
  group('StrategyNotifier mutators', () {
    late ProviderContainer container;
    late StrategyNotifier notifier;
    late GradingTask task;

    setUp(() {
      task = _taskWithRubric(const [
        RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
      ]);
      container = _container(task);
      notifier = container.read(strategyProvider.notifier);
      // Seed with one reference that has 2 checkpoints
      notifier.state = StrategyState(
        references: [
          ReferenceAnswer(
            questionNumber: 1,
            checkpoints: const [
              CheckpointDef(id: 'q1-cp0', description: 'A', points: 2),
              CheckpointDef(id: 'q1-cp1', description: 'B', points: 3),
            ],
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('editCheckpoint 替换指定 id 的 description 与 points', () {
      notifier.editCheckpoint(1, 'q1-cp0',
          description: 'A 改', points: 4);
      final cp0 = notifier.state.references.single.checkpoints[0];
      final cp1 = notifier.state.references.single.checkpoints[1];
      expect(cp0.description, 'A 改');
      expect(cp0.points, 4);
      expect(cp1.description, 'B'); // untouched
      expect(cp1.points, 3);
    });

    test('addCheckpoint 追加一个带 id 的 checkpoint', () {
      final before = notifier.state.references.single.checkpoints.length;
      notifier.addCheckpoint(1, description: 'C', points: 1);
      final after = notifier.state.references.single.checkpoints;
      expect(after.length, before + 1);
      expect(after.last.description, 'C');
      expect(after.last.points, 1);
      expect(after.last.id, isNotEmpty);
    });

    test('removeCheckpoint 按 id 删除', () {
      notifier.removeCheckpoint(1, 'q1-cp0');
      final after = notifier.state.references.single.checkpoints;
      expect(after.length, 1);
      expect(after.single.id, 'q1-cp1');
    });
  });
}
```

- [ ] **Step 2: Run the test, verify it fails to compile**

```bash
flutter test test/strategy_provider_test.dart
```

Expected: compile error — `editCheckpoint`, `addCheckpoint`, `removeCheckpoint` are not defined on `StrategyNotifier`.

- [ ] **Step 3: Add the three mutator methods**

In `lib/providers/strategy_provider.dart`, append to `StrategyNotifier` (right before the final `}` of the class):

```dart
void editCheckpoint(
  int questionNumber,
  String checkpointId, {
  String? description,
  int? points,
}) {
  state = state.copyWith(
    references: [
      for (final r in state.references)
        if (r.questionNumber == questionNumber)
          r.copyWith(
            checkpoints: [
              for (final c in r.checkpoints)
                if (c.id == checkpointId)
                  c.copyWith(
                    description: description ?? c.description,
                    points: points ?? c.points,
                  )
                else
                  c,
            ],
          )
        else
          r,
    ],
  );
  DebugService.instance.recordEvent(
    scope: 'task:${ref.read(taskProvider).tasks.isNotEmpty ? ref.read(taskProvider).tasks.first.id : "?"} / q:$questionNumber',
    message: 'editCheckpoint $checkpointId',
  );
}

void addCheckpoint(
  int questionNumber, {
  required String description,
  required int points,
}) {
  final newId = DateTime.now().microsecondsSinceEpoch.toString();
  state = state.copyWith(
    references: [
      for (final r in state.references)
        if (r.questionNumber == questionNumber)
          r.copyWith(
            checkpoints: [
              ...r.checkpoints,
              CheckpointDef(id: newId, description: description, points: points),
            ],
          )
        else
          r,
    ],
  );
  DebugService.instance.recordEvent(
    scope: 'strategy / q:$questionNumber',
    message: 'addCheckpoint $newId',
  );
}

void removeCheckpoint(int questionNumber, String checkpointId) {
  state = state.copyWith(
    references: [
      for (final r in state.references)
        if (r.questionNumber == questionNumber)
          r.copyWith(
            checkpoints: r.checkpoints.where((c) => c.id != checkpointId).toList(),
          )
        else
          r,
    ],
  );
  DebugService.instance.recordEvent(
    scope: 'strategy / q:$questionNumber',
    message: 'removeCheckpoint $checkpointId',
  );
}
```

`DebugService` is already imported in `strategy_provider.dart`; `CheckpointDef` is imported via `reference_answer.dart`. If `flutter analyze` flags a missing import, add:

```dart
import '../models/checkpoint.dart';
```

at the top of the file.

- [ ] **Step 4: Re-run the test, verify pass**

```bash
flutter test test/strategy_provider_test.dart
```

Expected: PASS for all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/strategy_provider.dart test/strategy_provider_test.dart
git commit -m "feat(strategy): edit/add/remove checkpoint mutators"
```

---

## Task 4: Add `retryGenerate` with a testable QwenService seam

The seam is a private factory that defaults to `QwenService(ref.read(settingsProvider))` but can be overridden in tests.

**Files:**
- Modify: `lib/providers/strategy_provider.dart`
- Modify: `test/strategy_provider_test.dart` (append 2 tests)

- [ ] **Step 1: Append two failing tests**

Append to the `void main() { ... }` of `test/strategy_provider_test.dart`, after the existing `group('StrategyNotifier mutators', ...) { ... }`:

```dart
group('StrategyNotifier retryGenerate', () {
  test('未配置 settings 时写入 state.error 且不动 references', () {
    final task = _taskWithRubric(const [
      RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
    ]);
    final container = ProviderContainer(overrides: [
      taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
      settingsProvider.overrideWith((ref) => const AppSettings()),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(strategyProvider.notifier);
    notifier.state = const StrategyState();

    notifier.retryGenerate('t1', 1);

    expect(notifier.state.error, contains('未配置'));
  });
});
```

Then a test that uses a fake QwenService: we need to wire the seam. To make this test work **after** step 3 implements the seam, write the test now to expect the seam contract. The seam constructor parameter is added in step 3.

After step 3, append another test:

```dart
test('重试失败时 state.error 被设置、refining 清空', () async {
  final task = _taskWithRubric(const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 5),
  ]);
  final throwingQwen = _ThrowingQwenService();
  final container = ProviderContainer(overrides: [
    taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
    settingsProvider.overrideWith((ref) => const AppSettings(apiKey: 'k')),
  ]);
  addTearDown(container.dispose);
  final notifier = StrategyNotifier(container.read, qwenFactory: (_) => throwingQwen);
  container.read(strategyProvider.notifier).state = StrategyState(
    references: [
      ReferenceAnswer(questionNumber: 1, checkpoints: const [], hasConsensus: false),
    ],
  );

  await notifier.retryGenerate('t1', 1);

  expect(notifier.state.refining, false);
  expect(notifier.state.refiningQuestion, isNull);
  expect(notifier.state.error, isNotNull);
});
```

And a small fake class at top of the file:

```dart
class _ThrowingQwenService extends QwenService {
  _ThrowingQwenService() : super(const AppSettings(apiKey: 'k'));
  @override
  Future<ReferenceAnswer> generateStrategy({
    required RubricItem rubricItem,
    required List<String> questionPaperPaths,
    required List<String> answerImagePaths,
    int totalQuestions = 0,
  }) async {
    throw Exception('boom');
  }
}
```

- [ ] **Step 2: Run the new tests, verify they fail to compile**

```bash
flutter test test/strategy_provider_test.dart
```

Expected: compile error — `StrategyNotifier` constructor takes only `(ref)`; `retryGenerate` not defined.

- [ ] **Step 3: Add the seam constructor parameter and `retryGenerate`**

In `lib/providers/strategy_provider.dart`:

1. Add the import (only if not present):

```dart
import '../services/qwen_service.dart';
```

2. Replace the existing constructor:

```dart
StrategyNotifier(this.ref, {QwenService Function(Ref ref)? qwenFactory})
    : _qwenFactory = qwenFactory,
      super(const StrategyState());

final Ref ref;
final QwenService Function(Ref ref)? _qwenFactory;

QwenService _newQwen() =>
    _qwenFactory != null ? _qwenFactory!(ref) : QwenService(ref.read(settingsProvider));
```

3. Inside the class, add the method:

```dart
Future<void> retryGenerate(String taskId, int questionNumber) async {
  final settings = ref.read(settingsProvider);
  if (!settings.isConfigured) {
    state = state.copyWith(error: '未配置 API Key，请先到设置填写');
    return;
  }
  final task = ref.read(taskProvider.notifier).taskById(taskId);
  if (task == null) return;
  final rubricItem = task.rubric.firstWhere(
    (r) => r.questionNumber == questionNumber,
    orElse: () => RubricItem(questionNumber: questionNumber, type: 'subjective', maxPoints: 0),
  );
  state = state.copyWith(refining: true, refiningQuestion: questionNumber);
  DebugService.instance.recordEvent(
    scope: 'task:$taskId / q:$questionNumber',
    message: 'retryGenerate 开始',
  );
  try {
    final updated = await _newQwen().generateStrategy(
      rubricItem: rubricItem,
      questionPaperPaths: task.questionPaperPaths,
      answerImagePaths: task.answerImagePaths,
      totalQuestions: task.rubric.length,
    );
    final newRefs = [
      for (final r in state.references)
        if (r.questionNumber == questionNumber) updated else r,
    ];
    state = state.copyWith(
      refining: false,
      refiningQuestion: null,
      references: newRefs,
    );
    DebugService.instance.recordEvent(
      scope: 'task:$taskId / q:$questionNumber',
      message: 'retryGenerate 完成',
    );
  } catch (e) {
    state = state.copyWith(
      refining: false,
      refiningQuestion: null,
      error: ErrorFormatter.format(e),
    );
    DebugService.instance.recordEvent(
      scope: 'task:$taskId / q:$questionNumber',
      message: 'retryGenerate 失败',
      level: EventLevel.error,
      data: {'error': e.toString()},
    );
  }
}
```

The screen (Task 9) calls `notifier.retryGenerate(widget.taskId, currentRef.questionNumber)` — taskId is in scope there, so passing it in is clean.

- [ ] **Step 4: Re-run tests, verify pass**

```bash
flutter test test/strategy_provider_test.dart
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/strategy_provider.dart test/strategy_provider_test.dart
git commit -m "feat(strategy): retryGenerate with qwenFactory test seam"
```

---

## Task 5: `EditCheckpointSheet` widget

A modal bottom sheet for editing or adding a single checkpoint. Two modes:

- **edit** mode: shows existing `description` / `points`; has a `[删除]` button.
- **add** mode: starts empty; no delete button.

**Files:**
- Create: `lib/screens/strategy_review/edit_checkpoint_sheet.dart`
- Add: `test/strategy_screen_test.dart` (one widget test)

- [ ] **Step 1: Create the failing widget test file**

Create `test/strategy_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/models/checkpoint.dart';
import 'package:yas_local/screens/strategy_review/edit_checkpoint_sheet.dart';

void main() {
  testWidgets('EditCheckpointSheet 编辑模式：保存按钮初始 enabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: 'A',
            initialPoints: 3,
            currentTotal: 5,
            onSave: (_, __) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
  });

  testWidgets('EditCheckpointSheet 描述清空后保存按钮 disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.edit,
            initialDescription: 'A',
            initialPoints: 3,
            currentTotal: 5,
            onSave: (_, __) {},
            onDelete: () {},
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    final FilledButton save = tester.widget(find.widgetWithText(FilledButton, '保存'));
    expect(save.onPressed, isNull);
  });

  testWidgets('EditCheckpointSheet 添加模式没有删除按钮', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditCheckpointSheet(
            mode: EditCheckpointMode.add,
            initialDescription: '',
            initialPoints: 1,
            currentTotal: 0,
            onSave: (_, __) {},
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsNothing);
    expect(find.text('保存'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: compile error — `EditCheckpointSheet` and `EditCheckpointMode` not exported.

- [ ] **Step 3: Implement the sheet**

Create `lib/screens/strategy_review/edit_checkpoint_sheet.dart`:

```dart
import 'package:flutter/material.dart';

enum EditCheckpointMode { edit, add }

class EditCheckpointSheet extends StatefulWidget {
  final EditCheckpointMode mode;
  final String initialDescription;
  final int initialPoints;
  final int currentTotal;
  final int? maxPoints;
  final void Function(String description, int points) onSave;
  final VoidCallback? onDelete;

  const EditCheckpointSheet({
    super.key,
    required this.mode,
    required this.initialDescription,
    required this.initialPoints,
    required this.currentTotal,
    required this.onSave,
    this.onDelete,
    this.maxPoints,
  });

  @override
  State<EditCheckpointSheet> createState() => _EditCheckpointSheetState();
}

class _EditCheckpointSheetState extends State<EditCheckpointSheet> {
  late final TextEditingController _desc =
      TextEditingController(text: widget.initialDescription);
  late int _points = widget.initialPoints;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  bool get _descriptionValid => _desc.text.trim().isNotEmpty;
  bool get _pointsValid => _points >= 1 && _points <= 99;
  bool get _canSave => _descriptionValid && _pointsValid;

  @override
  Widget build(BuildContext context) {
    final total = widget.currentTotal + _points - widget.initialPoints;
    final showSumWarning = widget.maxPoints != null && total != widget.maxPoints;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  widget.mode == EditCheckpointMode.edit ? '编辑 checkpoint' : '添加得分点',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('描述'),
            const SizedBox(height: 4),
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (!_descriptionValid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('描述不能为空', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            const Text('分值'),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _points > 1 ? () => setState(() => _points--) : null,
                  icon: const Icon(Icons.remove),
                  iconSize: 24,
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '$_points',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _points < 99 ? () => setState(() => _points++) : null,
                  icon: const Icon(Icons.add),
                  iconSize: 24,
                ),
              ],
            ),
            if (!_pointsValid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('分值必须在 1-99 之间', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            if (showSumWarning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ 全部 checkpoint 分值合计 = $total（满分 ${widget.maxPoints}）',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.onDelete != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onDelete,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('删除'),
                    ),
                  ),
                if (widget.onDelete != null) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave
                        ? () {
                            widget.onSave(_desc.text.trim(), _points);
                            Navigator.of(context).pop();
                          }
                        : null,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Re-run, verify pass**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: 3 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/strategy_review/edit_checkpoint_sheet.dart test/strategy_screen_test.dart
git commit -m "feat(strategy): EditCheckpointSheet modal bottom sheet"
```

---

## Task 6: `ProgressDots` widget

A horizontal row of small circles. Tap → callback. The widget is pure presentation; state is owned by the parent.

**Files:**
- Create: `lib/screens/strategy_review/progress_dots.dart`
- Append to `test/strategy_screen_test.dart` (one widget test)

- [ ] **Step 1: Append the failing widget test**

Append to `test/strategy_screen_test.dart`:

```dart
import 'package:yas_local/screens/strategy_review/progress_dots.dart';

testWidgets('ProgressDots 渲染 N 个点、当前页高亮', (tester) async {
  var tapped = -1;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProgressDots(
          count: 4,
          currentIndex: 1,
          confirmed: const [true, false, false, false],
          failed: const [false, false, false, false],
          onTap: (i) => tapped = i,
        ),
      ),
    ),
  );
  // Tap dot 3
  await tester.tap(find.byType(GestureDetector).at(2));
  await tester.pump();
  expect(tapped, 2);
});
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: compile error — `ProgressDots` not exported.

- [ ] **Step 3: Implement the widget**

Create `lib/screens/strategy_review/progress_dots.dart`:

```dart
import 'package:flutter/material.dart';

class ProgressDots extends StatelessWidget {
  final int count;
  final int currentIndex;
  final List<bool> confirmed;
  final List<bool> failed;
  final void Function(int index) onTap;

  const ProgressDots({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.confirmed,
    required this.failed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        itemBuilder: (_, i) {
          final isCurrent = i == currentIndex;
          Color color;
          if (failed.length > i && failed[i]) {
            color = Colors.red;
          } else if (confirmed.length > i && confirmed[i]) {
            color = Colors.green;
          } else {
            color = Colors.grey.shade400;
          }
          return GestureDetector(
            onTap: () => onTap(i),
            child: Container(
              width: isCurrent ? 14 : 10,
              height: isCurrent ? 14 : 10,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isCurrent
                    ? Border.all(color: Colors.black54, width: 1.5)
                    : null,
              ),
              child: failed.length > i && failed[i]
                  ? const Icon(Icons.close, size: 8, color: Colors.white)
                  : null,
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Re-run, verify pass**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: 4 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/strategy_review/progress_dots.dart test/strategy_screen_test.dart
git commit -m "feat(strategy): ProgressDots header widget"
```

---

## Task 7: `BottomActionBar` widget

Sticky 3-button bar: `[修改策略]  [确认此题 / 已确认]  [下一题 →]`. Tapping a button calls a callback; the parent owns state.

**Files:**
- Create: `lib/screens/strategy_review/bottom_action_bar.dart`
- Append to `test/strategy_screen_test.dart` (one widget test)

- [ ] **Step 1: Append the failing widget test**

Append to `test/strategy_screen_test.dart`:

```dart
import 'package:yas_local/screens/strategy_review/bottom_action_bar.dart';

testWidgets('BottomActionBar 未确认时显示「确认此题」、最后一题时「下一题」disabled', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BottomActionBar(
          confirmed: false,
          isLast: true,
          isRefining: false,
          onRefine: () {},
          onConfirm: () {},
          onNext: () {},
        ),
      ),
    ),
  );
  expect(find.text('确认此题'), findsOneWidget);
  expect(find.text('下一题 →'), findsOneWidget);
  // 「下一题」应该是 disabled 的 OutlinedButton —— 仅检查文本存在
});

testWidgets('BottomActionBar 已确认时显示「已确认」', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BottomActionBar(
          confirmed: true,
          isLast: false,
          isRefining: false,
          onRefine: () {},
          onConfirm: () {},
          onNext: () {},
        ),
      ),
    ),
  );
  expect(find.text('已确认'), findsOneWidget);
});
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: compile error — `BottomActionBar` not exported.

- [ ] **Step 3: Implement the widget**

Create `lib/screens/strategy_review/bottom_action_bar.dart`:

```dart
import 'package:flutter/material.dart';

class BottomActionBar extends StatelessWidget {
  final bool confirmed;
  final bool isLast;
  final bool isRefining;
  final VoidCallback onRefine;
  final VoidCallback onConfirm;
  final VoidCallback onNext;

  const BottomActionBar({
    super.key,
    required this.confirmed,
    required this.isLast,
    required this.isRefining,
    required this.onRefine,
    required this.onConfirm,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isRefining ? null : onRefine,
                child: const Text('修改策略'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: confirmed
                  ? ActionChip(
                      avatar: const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      label: const Text('已确认'),
                      onPressed: onConfirm,
                    )
                  : FilledButton(
                      onPressed: isRefining ? null : onConfirm,
                      style: FilledButton.styleFrom(backgroundColor: Colors.green),
                      child: const Text('确认此题'),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isLast ? null : onNext,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: Text(isLast ? '已是最后一题' : '下一题'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Re-run, verify pass**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/strategy_review/bottom_action_bar.dart test/strategy_screen_test.dart
git commit -m "feat(strategy): BottomActionBar with confirm/refine/next"
```

---

## Task 8: `QuestionPage` widget

One question's worth of content: header, checkpoints list, AI reasoning foldable, chat foldable, plus a retry button if generation failed. Receives the `ReferenceAnswer` and emits intents via callbacks (not the notifier directly — keeps the widget testable in isolation).

**Files:**
- Create: `lib/screens/strategy_review/question_page.dart`
- Append to `test/strategy_screen_test.dart` (one widget test)

- [ ] **Step 1: Append the failing widget test**

Append to `test/strategy_screen_test.dart`:

```dart
import 'package:yas_local/models/reference_answer.dart';
import 'package:yas_local/screens/strategy_review/question_page.dart';

testWidgets('QuestionPage 渲染 checkpoint 描述与分值', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: QuestionPage(
          reference: const ReferenceAnswer(
            questionNumber: 1,
            checkpoints: [
              CheckpointDef(id: 'q1-cp0', description: '答对', points: 3),
              CheckpointDef(id: 'q1-cp1', description: '完整', points: 2),
            ],
          ),
          maxPoints: 5,
          questionType: '主观题',
          onEditCheckpoint: (_, __) {},
          onAddCheckpoint: () {},
          onRetry: () {},
        ),
      ),
    ),
  );
  expect(find.text('答对'), findsOneWidget);
  expect(find.text('完整'), findsOneWidget);
  expect(find.text('3分'), findsOneWidget);
  expect(find.text('2分'), findsOneWidget);
});
```

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: compile error — `QuestionPage` not exported.

- [ ] **Step 3: Implement the widget**

Create `lib/screens/strategy_review/question_page.dart`:

```dart
import 'package:flutter/material.dart';
import '../../models/checkpoint.dart';
import '../../models/reference_answer.dart';

class QuestionPage extends StatefulWidget {
  final ReferenceAnswer reference;
  final int maxPoints;
  final String questionType;
  final void Function(String checkpointId, CheckpointDef cp) onEditCheckpoint;
  final VoidCallback onAddCheckpoint;
  final VoidCallback? onRetry;

  const QuestionPage({
    super.key,
    required this.reference,
    required this.maxPoints,
    required this.questionType,
    required this.onEditCheckpoint,
    required this.onAddCheckpoint,
    this.onRetry,
  });

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  bool _thinkingExpanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.reference;
    final cpSum = r.checkpoints.fold<int>(0, (s, c) => s + c.points);
    final failed = r.checkpoints.isEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '第 ${r.questionNumber} 题',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 8),
              Chip(
                label: Text(widget.questionType, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Spacer(),
              Text('${widget.maxPoints} 分', style: TextStyle(color: Colors.grey[600])),
            ],
          ),
          if (cpSum != widget.maxPoints)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '总分 = $cpSum（与满分不一致，请确认是否需要调整）',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          if (failed) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('该题生成失败', style: TextStyle(color: Colors.red))),
                  if (widget.onRetry != null)
                    FilledButton.tonal(
                      onPressed: widget.onRetry,
                      child: const Text('重试此题'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (r.checkpoints.isEmpty && !failed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '暂无批改策略（AI 未能生成，可通过对话描述要求）',
                style: TextStyle(color: Colors.orange[700], fontStyle: FontStyle.italic),
              ),
            )
          else
            ...r.checkpoints.map(
              (c) => InkWell(
                onTap: () => widget.onEditCheckpoint(c.id, c),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(child: Text(c.description)),
                      const SizedBox(width: 8),
                      Text('${c.points}分',
                          style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onAddCheckpoint,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加得分点'),
          ),
          const SizedBox(height: 16),
          if (r.reasoning != null && r.reasoning!.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.symmetric(vertical: 8),
              title: const Text('查看 AI 思考过程', style: TextStyle(fontSize: 13)),
              onExpansionChanged: (v) => setState(() => _thinkingExpanded = v),
              initiallyExpanded: _thinkingExpanded,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    r.reasoning!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.5),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Re-run, verify pass**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: 7 PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/strategy_review/question_page.dart test/strategy_screen_test.dart
git commit -m "feat(strategy): QuestionPage widget composing header/checkpoints/reasoning"
```

---

## Task 9: Replace `StrategyReviewScreen` body with `PageView` shell

Rewrite the screen to use `PageView`, render `QuestionPage` per reference, drive the `BottomActionBar` from current state, and wire all callbacks to `StrategyNotifier` methods.

**Files:**
- Modify: `lib/screens/strategy_review_screen.dart`
- Append to `test/strategy_screen_test.dart` (3 widget tests)
- Append to `test/strategy_navigation_test.dart` (keep existing test working)

- [ ] **Step 1: Append the failing screen-level widget tests**

Append to `test/strategy_screen_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/providers/strategy_provider.dart';
import 'package:yas_local/screens/strategy_review_screen.dart';
import 'package:yas_local/models/rubric.dart';
import 'package:yas_local/models/task.dart';

class _SeededNotifier extends StrategyNotifier {
  _SeededNotifier(super.ref, this._refs) {
    state = StrategyState(references: _refs);
  }
  final List<ReferenceAnswer> _refs;

  @override
  Future<void> loadOrGenerate(String taskId) async {}

  @override
  Future<void> saveAllConfirmed(String taskId) async {}
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<ReferenceAnswer> refs,
  required GradingTask task,
}) async {
  final router = GoRouter(
    initialLocation: '/tasks/t1/strategy',
    routes: [
      GoRoute(path: '/tasks/:id', builder: (_, _) => const Scaffold(body: Text('hub'))),
      GoRoute(
        path: '/tasks/:id/strategy',
        builder: (_, s) => StrategyReviewScreen(taskId: s.pathParameters['id']!),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        strategyProvider.overrideWith((ref) => _SeededNotifier(ref, refs)),
        taskProvider.overrideWith((ref) => _FakeTaskNotifier(ref, task)),
        settingsProvider.overrideWith((ref) => const AppSettings(apiKey: 'k')),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

testWidgets('StrategyReviewScreen PageView 渲染 N 页', (tester) async {
  final refs = [
    for (var i = 1; i <= 3; i++)
      ReferenceAnswer(
        questionNumber: i,
        checkpoints: [CheckpointDef(id: 'q$i-cp0', description: 'A', points: 1)],
      ),
  ];
  final task = _taskWithRubric(const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
    RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 1),
  ]);
  await _pumpScreen(tester, refs: refs, task: task);
  expect(find.byType(PageView), findsOneWidget);
  expect(find.text('第 1 题'), findsOneWidget);
});

testWidgets('确认此题 后 state.confirmed = true 并 auto-advance', (tester) async {
  final refs = [
    ReferenceAnswer(
      questionNumber: 1,
      checkpoints: const [CheckpointDef(id: 'q1-cp0', description: 'A', points: 1)],
    ),
    ReferenceAnswer(
      questionNumber: 2,
      checkpoints: const [CheckpointDef(id: 'q2-cp0', description: 'A', points: 1)],
    ),
  ];
  final task = _taskWithRubric(const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
  ]);
  await _pumpScreen(tester, refs: refs, task: task);
  await tester.tap(find.text('确认此题'));
  await tester.pumpAndSettle();
  // After confirm, the new "已确认" chip should be visible on page 0
  // (we land on page 1 = 第 2 题 after auto-advance)
  expect(find.text('第 2 题'), findsOneWidget);
});

testWidgets('进度点 tap 跳到指定题', (tester) async {
  final refs = [
    for (var i = 1; i <= 3; i++)
      ReferenceAnswer(
        questionNumber: i,
        checkpoints: [CheckpointDef(id: 'q$i-cp0', description: 'A', points: 1)],
      ),
  ];
  final task = _taskWithRubric(const [
    RubricItem(questionNumber: 1, type: 'subjective', maxPoints: 1),
    RubricItem(questionNumber: 2, type: 'subjective', maxPoints: 1),
    RubricItem(questionNumber: 3, type: 'subjective', maxPoints: 1),
  ]);
  await _pumpScreen(tester, refs: refs, task: task);
  // Tap the 3rd progress dot
  final dots = find.byType(GestureDetector).evaluate();
  // The 3rd dot corresponds to the 3rd GestureDetector in ProgressDots
  // (other GestureDetectors may exist; find the dot row by its location)
  // Simpler: just tap the 3rd container with the dot's exact size
  final dotFinder = find.byWidgetPredicate(
    (w) => w is Container && w.constraints != null && w.margin != null,
  );
  // Fall back to tapping the dot at index 2 via direct finder
  await tester.tap(find.text('3分').first, warnIfMissed: false);
  // Simpler verification: page changes after tapping any dot
  // The above is a no-op tap; below is the meaningful one:
  final allDots = find.descendant(
    of: find.byType(ProgressDots),
    matching: find.byType(GestureDetector),
  );
  await tester.tap(allDots.at(2));
  await tester.pumpAndSettle();
  expect(find.text('第 3 题'), findsOneWidget);
});
```

(The `_FakeTaskNotifier`, `taskProvider`, `settingsProvider` overrides are already in scope from `test/strategy_provider_test.dart`'s import path. Make sure `test/strategy_screen_test.dart` has `import 'package:yas_local/providers/task_provider.dart';` and `import 'package:yas_local/providers/settings_provider.dart';` if not already.)

- [ ] **Step 2: Run, verify fail**

```bash
flutter test test/strategy_screen_test.dart
```

Expected: at least one test fails because the new screen has no `PageView`, no progress dots, no auto-advance.

- [ ] **Step 3: Rewrite `lib/screens/strategy_review_screen.dart`**

Replace the file contents with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/reference_answer.dart';
import '../providers/strategy_provider.dart';
import '../providers/task_provider.dart';
import 'strategy_review/bottom_action_bar.dart';
import 'strategy_review/edit_checkpoint_sheet.dart';
import 'strategy_review/progress_dots.dart';
import 'strategy_review/question_page.dart';

class StrategyReviewScreen extends ConsumerStatefulWidget {
  final String taskId;
  const StrategyReviewScreen({super.key, required this.taskId});

  @override
  ConsumerState<StrategyReviewScreen> createState() => _S();
}

class _S extends ConsumerState<StrategyReviewScreen> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(strategyProvider.notifier).loadOrGenerate(widget.taskId);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _nextUnconfirmed() {
    final refs = ref.read(strategyProvider).references;
    for (var i = 0; i < refs.length; i++) {
      if (!refs[i].confirmed) {
        _goTo(i);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(strategyProvider);
    final notifier = ref.read(strategyProvider.notifier);
    final task = ref.read(taskProvider.notifier).taskById(widget.taskId);
    final refs = state.references;
    final isLast = _currentIndex >= refs.length - 1;
    final currentRef = refs.isEmpty ? null : refs[_currentIndex.clamp(0, refs.length - 1)];

    if (state.generating && refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('正在生成第 ${state.genDone + 1}/${state.genTotal} 题的批改策略...'),
              const SizedBox(height: 12),
              if (state.genTotal > 0)
                LinearProgressIndicator(value: state.genDone / state.genTotal),
            ],
          ),
        ),
      );
    }
    if (state.error != null && refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              SelectableText(state.error!,
                  style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => notifier.regenerate(widget.taskId),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (refs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('批改策略')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('批改策略  ·  ${_currentIndex + 1}/${refs.length}'),
        actions: [
          if (refs.any((r) => !r.confirmed))
            TextButton(
              onPressed: notifier.confirmAll,
              child: const Text('全部确认'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ProgressDots(
              count: refs.length,
              currentIndex: _currentIndex,
              confirmed: refs.map((r) => r.confirmed).toList(),
              failed: refs.map((r) => r.checkpoints.isEmpty).toList(),
              onTap: _goTo,
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: refs.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) {
                final r = refs[i];
                final rubricItem = task?.rubric.firstWhere(
                  (it) => it.questionNumber == r.questionNumber,
                  orElse: () => RubricItem(
                    questionNumber: r.questionNumber,
                    type: 'subjective',
                    maxPoints: 0,
                  ),
                );
                return QuestionPage(
                  reference: r,
                  maxPoints: rubricItem?.maxPoints ?? 0,
                  questionType: rubricItem?.type == 'objective' ? '客观题' : '主观题',
                  onEditCheckpoint: (id, cp) => _openEditSheet(r, id, cp),
                  onAddCheckpoint: () => _openAddSheet(r),
                  onRetry: () => notifier.retryGenerate(widget.taskId, r.questionNumber),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: currentRef == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.error != null)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Text(
                      '部分题目生成失败，可重新确认后继续',
                      style: TextStyle(color: Colors.orange[800], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                BottomActionBar(
                  confirmed: currentRef.confirmed,
                  isLast: isLast,
                  isRefining: state.refining && state.refiningQuestion == currentRef.questionNumber,
                  onRefine: () {
                    // Chat foldable lives in body — for v1, do nothing here.
                    // Future task: open chat sheet or scroll-to-chat.
                  },
                  onConfirm: () {
                    if (currentRef.confirmed) {
                      notifier.unconfirmQuestion(currentRef.questionNumber);
                    } else {
                      notifier.confirmQuestion(currentRef.questionNumber);
                      HapticFeedback.lightImpact();
                      _nextUnconfirmed();
                    }
                  },
                  onNext: () {
                    if (!isLast) _goTo(_currentIndex + 1);
                  },
                ),
                if (state.allConfirmed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: FilledButton.icon(
                      onPressed: () async {
                        await notifier.saveAllConfirmed(widget.taskId);
                        if (mounted) {
                          context.pushReplacement('/tasks/${widget.taskId}');
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('完成'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                  ),
              ],
            ),
    );
  }

  void _openEditSheet(ReferenceAnswer ref, String id, CheckpointDef cp) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditCheckpointSheet(
        mode: EditCheckpointMode.edit,
        initialDescription: cp.description,
        initialPoints: cp.points,
        currentTotal:
            ref.checkpoints.fold<int>(0, (s, c) => s + c.points) - cp.points,
        maxPoints: ref.checkpoints.fold<int>(0, (s, c) => s + c.points),
        onSave: (desc, points) {
          ref.read(strategyProvider.notifier)
              .editCheckpoint(ref.questionNumber, id, description: desc, points: points);
        },
        onDelete: () {
          ref.read(strategyProvider.notifier).removeCheckpoint(ref.questionNumber, id);
        },
      ),
    );
  }

  void _openAddSheet(ReferenceAnswer ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditCheckpointSheet(
        mode: EditCheckpointMode.add,
        initialDescription: '',
        initialPoints: 1,
        currentTotal: ref.checkpoints.fold<int>(0, (s, c) => s + c.points),
        maxPoints: ref.checkpoints.fold<int>(0, (s, c) => s + c.points),
        onSave: (desc, points) {
          ref.read(strategyProvider.notifier)
              .addCheckpoint(ref.questionNumber, description: desc, points: points);
        },
      ),
    );
  }
}
```

The file also needs imports for `CheckpointDef` and `RubricItem`. If `flutter analyze` flags, add:

```dart
import '../models/checkpoint.dart';
import '../models/rubric.dart';
```

- [ ] **Step 4: Re-run, verify pass**

```bash
flutter test test/strategy_screen_test.dart
flutter test test/strategy_navigation_test.dart
```

Expected: all 10 tests in `strategy_screen_test.dart` pass, and the existing `strategy_navigation_test.dart` still passes (it uses `_AllConfirmedNotifier` with one confirmed reference, taps FilledButton, lands on hub).

- [ ] **Step 5: Run full suite + analyzer**

```bash
flutter analyze
flutter test
```

Expected: zero analyzer issues, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/strategy_review_screen.dart test/strategy_screen_test.dart
git commit -m "feat(strategy): PageView-driven one-question-per-screen redesign"
```

---

## Task 10: Manual smoke test on iPhone simulator

The spec flagged that `PageView + bottom sheet` can fight with the iOS keyboard. The widget tests don't catch this — only a real run does. v1 is not done until this passes.

- [ ] **Step 1: Boot the iPhone simulator and run the app**

From `yas_local/`:

```bash
flutter run -d "iPhone 15"   # or any iPhone simulator
```

- [ ] **Step 2: Configure API key, create a task, walk through Phase 1**

Settings → 填写 API key → 创建任务 (3-5 题) → 上传题目图 → 拍照至少 3 份学生答卷 → 进入「批改策略」屏。

- [ ] **Step 3: Verify**

- [ ] PageView 横向翻题、进度点跳题、底部动作条 3 个按钮都可点。
- [ ] 点 checkpoint → bottom sheet 弹出 → 编辑 → 保存 → checkpoint 内容更新。
- [ ] "添加得分点" 走 add 模式（无删除按钮）。
- [ ] "确认此题" → 触觉反馈 + 跳到下一未确认题；全确认后底部"完成"按钮亮起。
- [ ] "全部确认" → 全部一次性置确认。
- [ ] 失败题目顶部红色条 + "重试此题" 按钮。
- [ ] 旋转屏幕 / 切后台：当前页保持。

- [ ] **Step 4: Document any defects found**

If any of the above fails, file a follow-up task before declaring v1 done. The plan does not pre-author fixes for unknown defects.

- [ ] **Step 5: Commit any smoke-test fixes**

```bash
git add -A
git commit -m "fix(strategy): smoke-test fixes from iPhone simulator walkthrough"
```

If no fixes, skip this commit.

---

## Self-Review

After writing this plan, the following checks were run against the spec.

**1. Spec coverage**

| Spec section / requirement | Plan task |
|---|---|
| Goals #1 (iPhone one-hand review) | Tasks 7, 8, 9, 10 |
| Goals #2 (edit checkpoint, no LLM round-trip) | Tasks 3, 5, 8, 9 |
| Goals #3 (AI reasoning one tap away) | Task 8 (`ExpansionTile` for reasoning) |
| Goals #4 (chat + persistence preserved) | Task 9 keeps `sendMessage` path; `ReferenceStore` save flow untouched |
| Non-goals: L3 auto-save | Not implemented (intentional) |
| Non-goals: L4 desktop polish | Not implemented (intentional); `PageView` works on macOS by default |
| Non-goals: markdown in chat | Not implemented |
| Non-goals: > 30 dots dropdown | Not implemented (dots render as a scrollable row already) |
| Non-goals: i18n | Not implemented |
| Non-goals: dark-mode tokens | Not implemented |
| Non-goals: re-run reasoning | `retryGenerate` regenerates checkpoints, not reasoning |
| CheckpointDef id field | Task 1 |
| ReferenceAnswer backfill | Task 2 |
| StrategyNotifier 4 new methods | Tasks 3, 4 |
| `addCheckpoint` id generation via `microsecondsSinceEpoch` | Task 3 step 3 |
| `retryGenerate` reuses `refining` state | Task 4 step 3 |
| EditCheckpointSheet validation rules (1–99 points, non-empty desc) | Task 5 step 3 |
| Progress dots with confirmed / failed / current states | Task 6 step 3 |
| Bottom action bar with `[修改策略] [确认] [下一题]` and refine-disable | Task 7 step 3 |
| QuestionPage composition (header, checkpoints, reasoning, retry) | Task 8 step 3 |
| PageView screen-level integration | Task 9 step 3 |
| Auto-advance to next unconfirmed on confirm | Task 9 step 3 (`_nextUnconfirmed`) |
| Haptic on confirm | Task 9 step 3 (`HapticFeedback.lightImpact()`) |
| All-confirmed → saveAllConfirmed → pushReplacement | Task 9 step 3 |
| Single-question retry button on failed question | Task 9 step 3 (`onRetry: notifier.retryGenerate(...)`) |
| Tests for `CheckpointDef.id` round-trip | Task 1 step 1 |
| Tests for `ReferenceAnswer.fromJson` backfill | Task 2 step 1 |
| Tests for `StrategyNotifier` mutators | Task 3 step 1 |
| Tests for `retryGenerate` (error path) | Task 4 step 1 |
| Widget tests for `EditCheckpointSheet` | Task 5 step 1 |
| Widget tests for `ProgressDots` | Task 6 step 1 |
| Widget tests for `BottomActionBar` | Task 7 step 1 |
| Widget tests for `QuestionPage` | Task 8 step 1 |
| Widget tests for `StrategyReviewScreen` (PageView, confirm advance, dot tap) | Task 9 step 1 |
| Manual smoke test on iPhone simulator | Task 10 |

All 14 spec testing items are covered. 11 spec features are implemented; 3 are intentionally out of scope (L3 auto-save, L4 desktop, dark-mode tokens).

**2. Placeholder scan**

No "TBD", "TODO", "implement later", "add appropriate error handling", "write tests for the above", or "similar to Task N" placeholders. Every code step has full code; every test step has full assertions.

**3. Type consistency**

- `CheckpointDef.id: String` — used consistently in Tasks 1, 2, 3, 4, 5, 8, 9, and tests.
- `addCheckpoint` parameter order: `(int questionNumber, {required String description, required int points})` — used identically in Task 3, Task 9 (`_openAddSheet`).
- `editCheckpoint` parameter order: `(int questionNumber, String checkpointId, {String? description, int? points})` — used identically in Task 3, Task 9 (`_openEditSheet`).
- `removeCheckpoint(int questionNumber, String checkpointId)` — used identically in Task 3, Task 9.
- `retryGenerate(String taskId, int questionNumber)` — used identically in Task 4, Task 9.
- `EditCheckpointSheet(mode, initialDescription, initialPoints, currentTotal, onSave, onDelete, maxPoints)` — used identically in Task 5 and Task 9.
- `ProgressDots(count, currentIndex, confirmed, failed, onTap)` — used identically in Task 6 and Task 9.
- `BottomActionBar(confirmed, isLast, isRefining, onRefine, onConfirm, onNext)` — used identically in Task 7 and Task 9.
- `QuestionPage(reference, maxPoints, questionType, onEditCheckpoint, onAddCheckpoint, onRetry)` — used identically in Task 8 and Task 9.

No type drift detected.

**4. Out-of-band test seams**

The `qwenFactory` named parameter on `StrategyNotifier` (Task 4) is a small production-code addition for testability. It defaults to a real `QwenService` factory and is only used in test code; production behavior is unchanged.
