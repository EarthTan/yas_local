import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yas_local/services/error_formatter.dart' as ef;

void main() {
  group('formatDioError', () {
    test('truncates URL past 80 chars', () {
      // Long URL with the key at the tail so substring(0, 80) cuts the
      // secret off and the formatted message no longer contains the full
      // key string.
      final msg = ef.ErrorFormatter.format(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?model=x&endpoint=foo&pad=01234567890123456789&key=sk-abcdef0123456789abcdef0123456789',
      ));
      expect(msg, isNot(contains('sk-abcdef0123456789abcdef0123456789')));
    });

    test('warns when URL contains ?key=', () {
      final msg = ef.ErrorFormatter.format(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?key=sk-abc',
      ));
      expect(msg, contains('URL 含 ?key='));
    });

    test('does not warn for clean URL', () {
      final msg = ef.ErrorFormatter.format(_stubError(
        url: 'https://api.foo.com/v1/chat/completions',
      ));
      expect(msg, isNot(contains('URL 含 ?key=')));
    });

    test('truncation is on the URL substring only, not the rest of the message', () {
      final msg = ef.ErrorFormatter.format(_stubError(
        url: 'https://api.foo.com/v1/chat/completions?key=sk-abc',
        body: 'real body content here',
      ));
      expect(msg, contains('real body content here'));
    });
  });
}

DioException _stubError({required String url, String? body}) {
  return DioException(
    requestOptions: RequestOptions(path: url),
    response: Response(
      requestOptions: RequestOptions(path: url),
      data: body,
    ),
    type: DioExceptionType.badResponse,
  );
}
