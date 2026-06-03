import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';

/// A 🐞 icon button that pushes /debug. Renders nothing when
/// settings.debugMode is false, so it can be placed in any AppBar's
/// `actions` list without conditional logic at the call site.
class DebugEntryButton extends ConsumerWidget {
  const DebugEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider).debugMode) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.bug_report),
      tooltip: 'Debug',
      onPressed: () => context.push('/debug'),
    );
  }
}
