import 'package:flutter/material.dart';
import '../../../services/debug/debug_export.dart';

class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.tab, required this.data});
  final String tab;
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.ios_share),
      tooltip: '导出为 JSON',
      onPressed: () => _onPressed(context),
    );
  }

  Future<void> _onPressed(BuildContext context) async {
    try {
      final file = await DebugExport.writeJson(tab, data);
      await DebugExport.reveal(file);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出: ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }
}
