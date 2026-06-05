import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'debug_service.dart';

/// Installs three Flutter framework error hooks so they flow into
/// [DebugService] as [EventRecord]s:
///
/// - [FlutterError.onError] -> scope `flutter_error`
/// - [PlatformDispatcher.instance.onError] -> scope `async_error`
/// - [ErrorWidget.builder] -> scope `flutter_error` (with `widgetError: true`
///   in `data` to distinguish build errors from framework assertions)
///
/// The zone-error hook is installed separately via [zoneErrorHandler] and
/// passed to `runZonedGuarded` in `main.dart` — see that function for the
/// rationale.
///
/// Idempotent: each handler is just an assignment, so calling this twice
/// safely replaces the previous handlers.
void installErrorHooks() {
  FlutterError.onError = (details) {
    DebugService.instance.recordEvent(
      scope: 'flutter_error',
      level: EventLevel.error,
      message: details.exceptionAsString(),
      data: {
        'library': details.library,
        'context': details.context?.toDescription(),
        'stack': details.stack?.toString(),
      },
    );
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    DebugService.instance.recordEvent(
      scope: 'async_error',
      level: EventLevel.error,
      message: error.toString(),
      data: {'stack': stack.toString()},
    );
    return true;
  };

  ErrorWidget.builder = (details) {
    DebugService.instance.recordEvent(
      scope: 'flutter_error',
      level: EventLevel.error,
      message: details.exceptionAsString(),
      data: {
        'widgetError': true,
        'stack': details.stack?.toString(),
      },
    );
    // Always render Flutter's default ErrorWidget so a broken widget is
    // visibly broken (gray box + error text) rather than invisibly blank.
    // The recordEvent above still captures the error to the debug log.
    return ErrorWidget(details.exception);
  };
}

/// The `onError` callback for `runZonedGuarded`. Records uncaught zone
/// errors as `zone_error` [EventRecord]s. Extracted as a named function
/// so tests can drive it without wrapping the test body in a zone.
void zoneErrorHandler(Object error, StackTrace stack) {
  DebugService.instance.recordEvent(
    scope: 'zone_error',
    level: EventLevel.error,
    message: error.toString(),
    data: {'stack': stack.toString()},
  );
}
