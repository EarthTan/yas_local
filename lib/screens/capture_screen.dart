import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/submission.dart';
import '../providers/task_provider.dart';
import '../services/image_store.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  final String taskId;
  const CaptureScreen({super.key, required this.taskId});
  @override
  ConsumerState<CaptureScreen> createState() => _S();
}

class _S extends ConsumerState<CaptureScreen> {
  final _picker = ImagePicker();
  final List<File> _photos = [];
  bool _busy = false;

  Future<void> _shoot() async {
    if (Platform.isMacOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('macOS 不支持直接拍照，请点击「相册」选择图片文件')),
        );
      }
      return;
    }
    try {
      final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (x != null && mounted) setState(() => _photos.add(File(x.path)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('相机出错：$e')));
      }
    }
  }

  Future<void> _pick() async {
    try {
      final xs = await _picker.pickMultiImage(imageQuality: 85);
      if (xs.isNotEmpty && mounted) {
        setState(() => _photos.addAll(xs.map((e) => File(e.path))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
      }
    }
  }

  Future<void> _start() async {
    if (_photos.isEmpty) return;
    setState(() => _busy = true);
    final subs = <Submission>[];
    for (var i = 0; i < _photos.length; i++) {
      final id = '${widget.taskId}_${DateTime.now().microsecondsSinceEpoch}_$i';
      final path = await ImageStore.persist(_photos[i].path, id);
      subs.add(Submission(id: id, taskId: widget.taskId, label: '第 ${i + 1} 份', imagePath: path));
    }
    await ref.read(taskProvider.notifier).setSubmissions(widget.taskId, subs);
    if (!mounted) return;
    context.pushReplacement('/tasks/${widget.taskId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传学生作业'),
        actions: [
          if (_photos.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _start,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('下一步 (${_photos.length})'),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _photos.isEmpty
              ? const Center(child: Text('点击下方拍照或从相册选择学生作业'))
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                  itemCount: _photos.length,
                  itemBuilder: (_, i) => Stack(fit: StackFit.expand, children: [
                    Image.file(_photos[i], fit: BoxFit.cover),
                    Positioned(top: 2, right: 2, child: GestureDetector(
                      onTap: () => setState(() => _photos.removeAt(i)),
                      child: const CircleAvatar(radius: 11, backgroundColor: Colors.red, child: Icon(Icons.close, size: 13, color: Colors.white)),
                    )),
                  ]),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: _shoot, icon: const Icon(Icons.camera_alt), label: const Text('拍照'))),
            const SizedBox(width: 12),
            Expanded(child: OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.photo_library), label: const Text('相册'))),
          ]),
        ),
      ]),
    );
  }
}
