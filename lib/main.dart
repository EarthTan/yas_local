import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'services/debug/debug_service.dart';
import 'services/debug/error_hooks.dart';
import 'services/debug/rolling_file_sink.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Always-on: ring buffer + on-disk NDJSON sink under
    // <applicationSupport>/log/yas_YYYY-MM-DD.log.
    DebugService.instance.setEnabled(true);
    DebugService.instance.addSink(await _buildRollingSink());

    installErrorHooks();

    runApp(const ProviderScope(child: YasApp()));
  }, zoneErrorHandler);
}

Future<RollingFileSink> _buildRollingSink() async {
  final dir = await getApplicationSupportDirectory();
  return RollingFileSink(
    directory: '${dir.path}/log',
    baseName: 'yas',
  );
}
