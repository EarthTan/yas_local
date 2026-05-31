import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../models/settings.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late TextEditingController _key;
  late TextEditingController _base;
  late TextEditingController _vl;
  late TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _key = TextEditingController(text: s.apiKey);
    _base = TextEditingController(text: s.baseUrl);
    _vl = TextEditingController(text: s.vlModel);
    _text = TextEditingController(text: s.textModel);
  }

  @override
  void dispose() {
    _key.dispose(); _base.dispose(); _vl.dispose(); _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).update(AppSettings(
          apiKey: _key.text.trim(),
          baseUrl: _base.text.trim(),
          vlModel: _vl.text.trim(),
          textModel: _text.text.trim(),
        ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('API 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _key, decoration: const InputDecoration(labelText: 'Qwen API Key', border: OutlineInputBorder()), obscureText: true),
          const SizedBox(height: 16),
          TextField(
            controller: _base,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/v1',
              helperText: '填写到 /v1 为止，无需包含 /chat/completions',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: _vl, decoration: const InputDecoration(labelText: '视觉模型（识别）', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          TextField(controller: _text, decoration: const InputDecoration(labelText: '文本模型（评语）', border: OutlineInputBorder())),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存')),
          const SizedBox(height: 8),
          const Text('Key 仅保存在本机，不上传任何服务器。', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }
}
