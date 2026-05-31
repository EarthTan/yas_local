import 'package:flutter/material.dart';

class GradingScreen extends StatelessWidget {
  final String taskId;
  const GradingScreen({super.key, required this.taskId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Grading')));
}
