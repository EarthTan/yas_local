import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yas_local/models/identified_question.dart';
import 'package:yas_local/providers/identification_provider.dart';
import 'package:yas_local/screens/identify_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Mock path_provider so the real TaskNotifier (created when the
  // IdentifyScreen reads taskProvider) doesn't blow up in widget tests.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '/tmp',
      );

  // Fake notifier: when `identify()` is called (from the screen's
  // post-frame callback in initState), it short-circuits the network
  // call by setting state to a fixed list of questions. The real
  // IdentificationNotifier takes only a Ref and exposes `state`
  // (an IdentificationState); we override the provider so we never
  // touch QwenService.
  _SeededIdentificationNotifier seed(Ref ref) =>
      _SeededIdentificationNotifier(ref);

  testWidgets(
    'IdentifyScreen 渲染识别出的题目列表（每道题一个 TextFormField，含题面）',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identificationProvider.overrideWith(seed),
          ],
          child: const MaterialApp(
            home: IdentifyScreen(taskId: 't1'),
          ),
        ),
      );
      // Pump a few frames: the post-frame callback in initState calls
      // identify(), and ref.listen fires to populate _editables. We use
      // a fixed number of pumps (not pumpAndSettle) because the loading
      // branch renders an indefinite CircularProgressIndicator.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      // AppBar title is "确认题目" once the questions have loaded.
      expect(find.text('确认题目'), findsOneWidget);
      // 第 1 题 / 第 2 题 section headers are rendered.
      expect(find.text('第 1 题'), findsOneWidget);
      expect(find.text('第 2 题'), findsOneWidget);
      // Each question's text is rendered inside a TextFormField. Since
      // TextFormField displays its controller's text, the test asserts
      // the form field with the seeded text is on screen.
      final firstField = find.widgetWithText(TextFormField, '一加一等于几？');
      expect(firstField, findsOneWidget);
      final secondField = find.widgetWithText(TextFormField, '二选一：A 或 B');
      expect(secondField, findsOneWidget);
    },
  );

  testWidgets(
    '编辑题面 TextFormField 后 controller 持有新文本（用户可改）',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identificationProvider.overrideWith(seed),
          ],
          child: const MaterialApp(
            home: IdentifyScreen(taskId: 't1'),
          ),
        ),
      );
      // Pump a few frames: post-frame callback fires identify(), the
      // ref.listen populates _editables, then the screen re-renders.
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      // Each question card has at least 2 TextFormFields (text + points);
      // objective questions get a 3rd (correct-answer). Question 1 is
      // subjective (2 fields), question 2 is objective (3 fields) → 5.
      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(5),
          reason: 'subjective has 2 fields + objective has 3 fields');
      final q1TextField = textFields.first;
      final q1Tf = tester.widget<TextFormField>(q1TextField);
      expect(q1Tf.controller?.text, '一加一等于几？');

      // Replace the controller's text via the form. enterText on a
      // TextFormField finder types into the underlying controller.
      await tester.enterText(q1TextField, '已编辑的题目');
      await tester.pump();

      // The TextFormField widget's controller now holds the new value.
      final q1TfAfter = tester.widget<TextFormField>(q1TextField);
      expect(q1TfAfter.controller?.text, '已编辑的题目');
    },
  );

  testWidgets(
    'back 按钮通过 Navigator 弹出 IdentifyScreen',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/identify',
            builder: (_, _) => const IdentifyScreen(taskId: 't1'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identificationProvider.overrideWith(seed),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // Navigate from / to /identify.
      router.push('/identify');
      await tester.pumpAndSettle();
      expect(find.text('确认题目'), findsOneWidget);

      // Tap the default leading BackButton in the AppBar.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // We're back on /.
      expect(find.text('home'), findsOneWidget);
      expect(find.text('确认题目'), findsNothing);
    },
  );
}

class _SeededIdentificationNotifier extends IdentificationNotifier {
  _SeededIdentificationNotifier(super.ref);

  @override
  Future<void> identify(String taskId) async {
    // Mirror the real notifier: set state to the seeded questions.
    // The screen's `ref.listen` only fires on state transitions, so a
    // direct `state =` assignment in the constructor doesn't trigger it.
    state = const IdentificationState(questions: [
      IdentifiedQuestion(number: 1, questionText: '一加一等于几？', type: 'subjective'),
      IdentifiedQuestion(number: 2, questionText: '二选一：A 或 B', type: 'objective'),
    ]);
  }
}
