import 'package:flutter/material.dart';

class CaptureScreen extends StatelessWidget {
  final String taskId;
  const CaptureScreen({super.key, required this.taskId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Capture')));
}
