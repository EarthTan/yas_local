import 'package:flutter/material.dart';

enum EditCheckpointMode { edit, add }

/// Modal bottom sheet for editing or adding a single checkpoint.
///
/// **Required inputs:**
/// - [initialDescription] / [initialPoints] — the checkpoint's current values
///   (used to pre-fill the form fields).
/// - [currentTotal] — the sum of OTHER checkpoints' points for the same question
///   (i.e., excluding this one). Used to compute the "all checkpoints now sum to X"
///   warning. In `edit` mode, the sheet's own [initialPoints] is not in [currentTotal];
///   in `add` mode, the new checkpoint isn't either.
/// - [maxPoints] — the question's total available points. When non-null and the
///   computed total (with the proposed edit applied) doesn't match, an orange
///   warning is shown. Non-blocking.
/// - [onSave] — receives the trimmed description and the new points value, then
///   the sheet pops itself. Caller is responsible for applying the change.
/// - [onDelete] — when non-null, a red "删除" button is shown. Sheet does not
///   pop after delete; the caller decides whether to confirm.
class EditCheckpointSheet extends StatefulWidget {
  final EditCheckpointMode mode;
  final String initialDescription;
  final int initialPoints;
  final int currentTotal;
  final int? maxPoints;
  final void Function(String description, int points) onSave;
  final VoidCallback? onDelete;

  const EditCheckpointSheet({
    super.key,
    required this.mode,
    required this.initialDescription,
    required this.initialPoints,
    required this.currentTotal,
    required this.onSave,
    this.onDelete,
    this.maxPoints,
  });

  @override
  State<EditCheckpointSheet> createState() => _EditCheckpointSheetState();
}

class _EditCheckpointSheetState extends State<EditCheckpointSheet> {
  late final TextEditingController _desc =
      TextEditingController(text: widget.initialDescription);
  late int _points = widget.initialPoints;

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  bool get _descriptionValid => _desc.text.trim().isNotEmpty;
  bool get _pointsValid => _points >= 1 && _points <= 99;
  bool get _canSave => _descriptionValid && _pointsValid;

  @override
  Widget build(BuildContext context) {
    // currentTotal contract: sum of OTHER checkpoints' points (excluding this one
    // for edit, or excluding the new one for add). Adding _points gives the
    // total the question will have once the proposed change is saved.
    final total = widget.currentTotal + _points;
    final showSumWarning = widget.maxPoints != null && total != widget.maxPoints;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  widget.mode == EditCheckpointMode.edit ? '编辑 checkpoint' : '添加得分点',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('描述'),
            const SizedBox(height: 4),
            TextField(
              controller: _desc,
              minLines: 3,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (!_descriptionValid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('描述不能为空', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            const SizedBox(height: 16),
            const Text('分值'),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: _points > 1 ? () => setState(() => _points--) : null,
                  icon: const Icon(Icons.remove),
                  iconSize: 24,
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '$_points',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _points < 99 ? () => setState(() => _points++) : null,
                  icon: const Icon(Icons.add),
                  iconSize: 24,
                ),
              ],
            ),
            if (!_pointsValid)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('分值必须在 1-99 之间', style: TextStyle(color: Colors.red, fontSize: 12)),
              ),
            if (showSumWarning)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ 全部 checkpoint 分值合计 = $total（满分 ${widget.maxPoints}）',
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.onDelete != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onDelete,
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('删除'),
                    ),
                  ),
                if (widget.onDelete != null) const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave
                        ? () {
                            widget.onSave(_desc.text.trim(), _points);
                            Navigator.of(context).pop();
                          }
                        : null,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
