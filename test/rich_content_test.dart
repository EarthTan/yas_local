import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/widgets/rich_content.dart';

void main() {
  group('normalizeLatexDelimiters', () {
    test('行内 \$\$...\$\$ 转换为 \\(...\\)', () {
      const input = r'见公式 $$E = mc^2$$ 所示';
      final result = normalizeLatexDelimiters(input);
      expect(result, equals(r'见公式 \(E = mc^2\) 所示'));
    });

    test('块级 \$\$\$\$...\$\$\$\$ 转换为 \\[...\\]', () {
      const input = r'$$$$E = mc^2$$$$';
      final result = normalizeLatexDelimiters(input);
      expect(result.contains(r'\['), isTrue);
      expect(result.contains('E = mc^2'), isTrue);
      expect(result.contains(r'\]'), isTrue);
    });

    test('块级先于行内处理：\$\$\$\$a+b\$\$\$\$ 不被行内规则截断', () {
      const input = r'$$$$a + b$$$$';
      final result = normalizeLatexDelimiters(input);
      expect(result.contains(r'\(a'), isFalse);
      expect(result.contains(r'\['), isTrue);
      expect(result.contains(r'\]'), isTrue);
    });

    test('同一段文字同时含行内和块级', () {
      const input = r'已知 $$x > 0$$，求解 $$$$\int_0^x t\,dt$$$$';
      final result = normalizeLatexDelimiters(input);
      expect(result.contains(r'\(x > 0\)'), isTrue);
      expect(result.contains(r'\['), isTrue);
    });

    test('纯 Markdown 文本原样透传', () {
      const input = '**加粗** 文字 <u>下划线</u>';
      expect(normalizeLatexDelimiters(input), equals(input));
    });

    test('空字符串不崩溃，返回空字符串', () {
      expect(normalizeLatexDelimiters(''), equals(''));
    });

    test('多行块级公式内容被保留', () {
      final input = r'$$$$' '\na + b\n= c\n' r'$$$$';
      final result = normalizeLatexDelimiters(input);
      expect(result.contains('a + b'), isTrue);
      expect(result.contains('= c'), isTrue);
      expect(result.contains(r'\['), isTrue);
    });
  });

  group('RichContent widget', () {
    testWidgets('纯文本不崩溃，渲染 MarkdownBody', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RichContent('普通文本'))),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('加粗 Markdown 不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RichContent('**加粗内容**'))),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('HTML 下划线 <u> 被消费（不以字面标签渲染）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
            home: Scaffold(body: RichContent('<u>下划线文本</u>'))),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
      // _HtmlUnderlineSyntax consumes <u>...</u> and emits an 'underline'
      // element — the raw tag characters must NOT appear as literal text.
      expect(find.text('<u>下划线文本</u>'), findsNothing);
    });

    testWidgets('行内 LaTeX 不崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichContent(r'公式 $$E = mc^2$$ 示例'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('块级 LaTeX 不崩溃', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RichContent(r'$$$$\int_0^\infty e^{-x}\,dx = 1$$$$'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('空字符串不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RichContent(''))),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('style 参数被接受不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RichContent('文字', style: TextStyle(fontSize: 20)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
    });
  });
}
