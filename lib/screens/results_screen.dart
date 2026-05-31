import 'package:flutter/material.dart';

class ResultsScreen extends StatelessWidget {
  final String taskId;
  const ResultsScreen({super.key, required this.taskId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Results')));
}
