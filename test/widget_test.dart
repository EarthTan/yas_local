import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yas_local/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: YasApp()));
    // First frame: loading state
    await tester.pump();
    // App bar with title should be visible immediately
    expect(find.text('YAS 批改助手'), findsOneWidget);
  });
}
