import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/task.dart';
import '../providers/task_provider.dart';
import '../services/image_store.dart';

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});
  @override
  ConsumerState<CreateTaskScreen> createState() => _S();
}

class _S extends ConsumerState<CreateTaskScreen> {
  final _picker = ImagePicker();
  final List<File> _questionPhotos = [];
  final List<File> _answerPhotos = [];
  final _title = TextEditingController();
  String _subject = 'math';
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  // --- Question photo pickers ---

  Future<void> _shootQuestion() async {
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
      if (x != null && mounted) setState(() => _questionPhotos.add(File(x.path)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('相机出错：$e')));
      }
    }
  }

  Future<void> _pickQuestion() async {
    try {
      final xs = await _picker.pickMultiImage(imageQuality: 85);
      if (xs.isNotEmpty && mounted) {
        setState(() => _questionPhotos.addAll(xs.map((e) => File(e.path))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
      }
    }
  }

  // --- Answer photo pickers ---

  Future<void> _shootAnswer() async {
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
      if (x != null && mounted) setState(() => _answerPhotos.add(File(x.path)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('相机出错：$e')));
      }
    }
  }

  Future<void> _pickAnswer() async {
    try {
      final xs = await _picker.pickMultiImage(imageQuality: 85);
      if (xs.isNotEmpty && mounted) {
        setState(() => _answerPhotos.addAll(xs.map((e) => File(e.path))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写任务名称')),
      );
      return;
    }
    if (_questionPhotos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少上传一张题目照片')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();

      final questionPaths = await ImageStore.persistQuestionImages(
        id,
        _questionPhotos.map((f) => f.path).toList(),
      );

      List<String> answerPaths = [];
      if (_answerPhotos.isNotEmpty) {
        answerPaths = await ImageStore.persistAnswerImages(
          id,
          _answerPhotos.map((f) => f.path).toList(),
        );
      }

      final task = GradingTask(
        id: id,
        name: _title.text.trim(),
        subject: _subject,
        createdAt: DateTime.now(),
        rubric: [],
        questionPaperPaths: questionPaths,
        answerImagePaths: answerPaths,
      );

      await ref.read(taskProvider.notifier).addTask(task);
      if (mounted) context.pushReplacement('/tasks/$id/identify');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建批改任务'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Section 1: Task name + Subject ---
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '任务名称（如：第3单元测验）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(
              labelText: '科目',
              border: OutlineInputBorder(),
            ),
            items: const [
              'math', 'chinese', 'english', 'physics',
              'chemistry', 'biology', 'history',
            ]
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v!),
          ),

          const SizedBox(height: 24),

          // --- Section 2: Question paper photos ---
          Text('1. 上传题目照片（必填）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _shootQuestion,
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickQuestion,
                icon: const Icon(Icons.photo_library),
                label: const Text('相册'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (_questionPhotos.isNotEmpty) ...[
            Text('已选 ${_questionPhotos.length} 张'),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1),
                itemCount: _questionPhotos.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_questionPhotos[i], fit: BoxFit.cover),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _questionPhotos.removeAt(i)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.red,
                            child: Icon(Icons.close,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // --- Section 3: Answer photos ---
          Text('2. 上传教师答案（可选）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _shootAnswer,
                icon: const Icon(Icons.camera_alt),
                label: const Text('拍照'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickAnswer,
                icon: const Icon(Icons.photo_library),
                label: const Text('相册'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (_answerPhotos.isNotEmpty) ...[
            Text('已选 ${_answerPhotos.length} 张'),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: GridView.builder(
                scrollDirection: Axis.horizontal,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 1),
                itemCount: _answerPhotos.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_answerPhotos[i], fit: BoxFit.cover),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _answerPhotos.removeAt(i)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.red,
                            child: Icon(Icons.close,
                                size: 13, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),

          // --- Save button ---
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search),
              label: Text(_busy ? '保存中...' : '保存并识别题目'),
            ),
          ),
        ],
      ),
    );
  }
}
