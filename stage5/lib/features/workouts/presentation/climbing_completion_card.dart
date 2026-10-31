import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/climbing_grade_field.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

class ClimbingCompletionCard extends ConsumerStatefulWidget {
  const ClimbingCompletionCard({
    required this.block,
    required this.recordingEnabled,
    required this.onChanged,
    this.initialInput,
    this.actual,
    this.exerciseContent,
    super.key,
  });
  final WorkoutBlock block;
  final bool recordingEnabled;
  final Map<String, dynamic>? initialInput;
  final ExerciseActual? actual;
  final Widget? exerciseContent;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  ConsumerState<ClimbingCompletionCard> createState() =>
      _ClimbingCompletionCardState();
}

class _ClimbingCompletionCardState
    extends ConsumerState<ClimbingCompletionCard> {
  late Map<String, dynamic> _input;
  bool get _isCircuit => widget.block is ClimbingCircuitBlock;
  String get _rowsKey => _isCircuit ? 'circuitRows' : 'freeRows';
  List<dynamic> get _rows => _input[_rowsKey] as List;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(ClimbingCompletionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInput != widget.initialInput) _restore();
  }

  void _restore() {
    final source = widget.initialInput ?? initialClimbingInput(widget.block);
    _input = {
      ...source,
      _rowsKey: [
        for (final row in source[_rowsKey] as List)
          Map<String, dynamic>.from(row as Map),
      ],
    };
  }

  void _emit() {
    _input.remove('rowIds');
    widget.onChanged({
      ..._input,
      _rowsKey: [
        for (final row in _rows) Map<String, dynamic>.from(row as Map)
      ],
    });
  }

  Widget _rpe(int? value, ValueChanged<int?> onChanged) =>
      DropdownButtonFormField<int>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'RPE (optional, 1–10)'),
        items: [
          const DropdownMenuItem<int>(value: null, child: Text('Not recorded')),
          for (var i = 1; i <= 10; i++)
            DropdownMenuItem(value: i, child: Text('$i')),
        ],
        onChanged: onChanged,
      );

  Widget _note(String value, String label, ValueChanged<String> onChanged) =>
      TextFormField(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        maxLength: 4000,
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_isCircuit ? 'Climbing Circuit' : 'Free Climbing',
                style: Theme.of(context).textTheme.titleMedium),
            if (_isCircuit)
              Text(block.slots.single.exerciseName ??
                  block.slots.single.exerciseId),
            if (widget.exerciseContent != null) widget.exerciseContent!,
            if (block.notes != null) Text('Trainer note: ${block.notes}'),
            if (block.videoUrl case final url?) ...[
              const Text('Drill video'),
              ExerciseVideoPreview(
                key: ValueKey('climbing-video-${block.blockId}'),
                url: url,
              ),
            ],
            if (widget.recordingEnabled) ...[
              if (!_isCircuit)
                const Text(
                    'Grade rows are optional. You can complete free climbing with only a note and RPE.'),
              for (var i = 0; i < _rows.length; i++) _buildRow(i),
              if (!_isCircuit)
                TextButton.icon(
                  onPressed: _rows.length < maxClimbingRows
                      ? () {
                          setState(() => _rows.add({
                                'rowId': ref
                                    .read(workoutTemplateRepositoryProvider)
                                    .generateExerciseSlotId(),
                                'gradingSystem':
                                    ClimbingGradingSystem.vScale.name,
                                'grade': 'V0',
                                'climbs': '',
                                'notes': '',
                              }));
                          _emit();
                        }
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add result row'),
                ),
              if (!_isCircuit)
                _rpe(_input['rpe'] as int?, (value) {
                  _input['rpe'] = value;
                  _emit();
                }),
              _note(_input['notes'] as String, 'Climbing note (optional)',
                  (value) {
                _input['notes'] = value;
                _emit();
              }),
            ] else
              ..._history(),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final row = _rows[index] as Map<String, dynamic>;
    final prescription =
        _isCircuit ? (widget.block as ClimbingCircuitBlock).rows[index] : null;
    return Padding(
      key: ValueKey(row['rowId']),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          if (prescription != null) ...[
            Text('${prescription.climbs} × ${prescription.grade}'
                '${prescription.maxAttemptsPerClimb == null ? '' : ' · Max ${prescription.maxAttemptsPerClimb} attempts per climb'}'),
            if (prescription.notes != null) Text(prescription.notes!),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Completed prescribed row'),
              value: row['completed'] as bool,
              onChanged: (value) {
                setState(() => row['completed'] = value!);
                _emit();
              },
            ),
            _rpe(row['rpe'] as int?, (value) {
              row['rpe'] = value;
              _emit();
            }),
          ] else ...[
            ClimbingGradeField(
              system: parseGradingSystem(row['gradingSystem']),
              grade: row['grade'] as String,
              onChanged: (system, grade) {
                setState(() {
                  row['gradingSystem'] = system.name;
                  row['grade'] = grade;
                });
                _emit();
              },
            ),
            TextFormField(
              initialValue: row['climbs'] as String,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Climbs completed'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => int.tryParse(value?.trim() ?? '') == null ||
                      int.parse(value!.trim()) < 1
                  ? 'Enter a positive whole number'
                  : null,
              onChanged: (value) {
                row['climbs'] = value;
                _emit();
              },
            ),
            TextButton(
              onPressed: () {
                setState(() => _rows.removeAt(index));
                _emit();
              },
              child: const Text('Remove result row'),
            ),
          ],
          _note(row['notes'] as String, 'Row note (optional)', (value) {
            row['notes'] = value;
            _emit();
          }),
        ],
      ),
    );
  }

  List<Widget> _history() {
    final actual = widget.actual;
    return [
      if (_isCircuit) ...[
        for (final prescription
            in (widget.block as ClimbingCircuitBlock).rows) ...[
          Text('${prescription.climbs} × ${prescription.grade}'
              '${prescription.maxAttemptsPerClimb == null ? '' : ' · Max ${prescription.maxAttemptsPerClimb} attempts per climb'}'),
          if (prescription.notes != null)
            Text('Prescribed note: ${prescription.notes}'),
          for (final row in actual?.circuitRows ?? <ClimbingCircuitResultRow>[])
            if (row.rowId == prescription.rowId)
              Text(
                '${row.completed ? 'Completed' : 'Not completed'}'
                '${row.rpe == null ? '' : ' · RPE ${row.rpe}'}'
                '${row.notes == null || row.notes!.isEmpty ? '' : ' · ${row.notes}'}',
              ),
        ],
      ],
      for (final row in actual?.freeRows ?? <FreeClimbingResultRow>[])
        Text(
            '${row.climbs} × ${row.grade}${row.notes == null || row.notes!.isEmpty ? '' : ' · ${row.notes}'}'),
      if (actual?.rpe != null) Text('RPE ${actual!.rpe}'),
      if (actual?.notes != null) Text('Climbing note: ${actual!.notes}'),
      if (actual == null) const Text('No result recorded'),
    ];
  }
}
