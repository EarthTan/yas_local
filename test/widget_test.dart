import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: YasApp()));
    await tester.pump();
    expect(find.text('YAS 批改助手'), findsOneWidget);
  });
}
