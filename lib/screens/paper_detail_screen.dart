import 'package:flutter/material.dart';

class PaperDetailScreen extends StatelessWidget {
  final String submissionId;
  const PaperDetailScreen({super.key, required this.submissionId});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Paper Detail')));
}
