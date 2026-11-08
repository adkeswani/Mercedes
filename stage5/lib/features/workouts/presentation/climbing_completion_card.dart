import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

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

class _ClimbingCompletionCardState extends ConsumerState<ClimbingCompletionCard>
    with AutomaticKeepAliveClientMixin {
  late Map<String, dynamic> _input;
  bool get _isCircuit => widget.block is ClimbingCircuitBlock;
  String get _rowsKey => _isCircuit ? 'circuitRows' : 'freeRows';
  List<dynamic> get _rows => _input[_rowsKey] as List;
  @override
  bool get wantKeepAlive => widget.recordingEnabled;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(ClimbingCompletionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialInput != widget.initialInput) _restore();
    if (oldWidget.recordingEnabled != widget.recordingEnabled) {
      updateKeepAlive();
    }
  }

  void _restore() {
    final source = climbingInputForStorage(
      widget.initialInput ?? initialClimbingInput(widget.block),
    );
    _input = {
      ...source,
      _rowsKey: [
        for (final row in source[_rowsKey] as List)
          Map<String, dynamic>.from(row as Map),
      ],
    };
  }

  void _updateRow(String id, String field, Object value) {
    final row = _rows.cast<Map>().singleWhere((row) => row['rowId'] == id);
    row[field] = value;
  }

  void _emit() {
    _input.remove('rowIds');
    widget.onChanged({
      ..._input,
      _rowsKey: [
        for (final row in _rows) Map<String, dynamic>.from(row as Map),
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
    super.build(context);
    final block = widget.block;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isCircuit ? 'Climbing Circuit' : 'Free Climbing',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (block is ClimbingCircuitBlock && block.hasExercise)
              Text(
                block.slots.single.exerciseName ??
                    block.slots.single.exerciseId,
              ),
            if (widget.exerciseContent != null) widget.exerciseContent!,
            if (block.notes != null) Text('Trainer note: ${block.notes}'),
            if (block.videoUrl case final url?) ...[
              const Text('Drill video'),
              ExerciseVideoPreview(
                key: ValueKey('climbing-video-${block.blockId}'),
                url: url,
              ),
            ],
            if (block is FreeClimbingBlock)
              ..._timers(
                block.blockId,
                block.workSeconds,
                block.restSeconds,
              ),
            if (widget.recordingEnabled) ...[
              for (var i = 0; i < _rows.length; i++) _buildRow(i),
              if (!_isCircuit)
                TextButton.icon(
                  onPressed: _rows.length < maxClimbingRows
                      ? () {
                          setState(
                            () => _rows.add({
                              'rowId': ref
                                  .read(workoutTemplateRepositoryProvider)
                                  .generateExerciseSlotId(),
                              'gradingSystem': _rows.isEmpty
                                  ? ClimbingGradingSystem.vScale.name
                                  : (_rows.last as Map)['gradingSystem'],
                              'grade': _rows.isEmpty
                                  ? 'V0'
                                  : (_rows.last as Map)['grade'],
                              'attempts': '1',
                              'sent': false,
                              'notes': '',
                            }),
                          );
                          _emit();
                        }
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add climb'),
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
    final id = row['rowId'] as String;
    final prescription =
        _isCircuit ? (widget.block as ClimbingCircuitBlock).rows[index] : null;
    return Padding(
      key: ValueKey<String>(row['rowId'] as String),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isCircuit) const Divider(),
          if (prescription != null) ...[
            Text('${prescription.climbs} × ${prescription.grade}'
                '${prescription.maxAttemptsPerClimb == null ? '' : ' · Max ${prescription.maxAttemptsPerClimb} attempts per climb'}'),
            if (prescription.notes != null) Text(prescription.notes!),
            ..._timers(
              '${widget.block.blockId}-${prescription.rowId}',
              prescription.workSeconds,
              prescription.restSeconds,
            ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: row['grade'] as String,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Grade',
                      isDense: true,
                    ),
                    items: [
                      for (final system in ClimbingGradingSystem.values)
                        for (final grade in system.grades)
                          DropdownMenuItem(value: grade, child: Text(grade)),
                    ],
                    onChanged: (grade) {
                      if (grade == null) return;
                      setState(() {
                        _updateRow(id, 'grade', grade);
                        _updateRow(
                          id,
                          'gradingSystem',
                          ClimbingGradingSystem.values
                              .singleWhere(
                                (system) => system.grades.contains(grade),
                              )
                              .name,
                        );
                      });
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 76,
                  child: TextFormField(
                    initialValue: row['attempts'] as String,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Attempts',
                      isDense: true,
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      final attempts = int.tryParse(value?.trim() ?? '');
                      return attempts == null || attempts < 1
                          ? 'Enter 1+'
                          : null;
                    },
                    onChanged: (value) {
                      _updateRow(id, 'attempts', value);
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  children: [
                    Text('Sent', style: Theme.of(context).textTheme.bodySmall),
                    Checkbox(
                      value: row['sent'] as bool,
                      semanticLabel: 'Climb ${index + 1} sent',
                      onChanged: (value) {
                        setState(() => _updateRow(id, 'sent', value!));
                        _emit();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
          if (_isCircuit)
            _note(row['notes'] as String, 'Row note (optional)', (value) {
              row['notes'] = value;
              _emit();
            })
          else
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: row['notes'] as String,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      isDense: true,
                    ),
                    maxLength: 4000,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) =>
                        null,
                    onChanged: (value) {
                      _updateRow(id, 'notes', value);
                      _emit();
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Remove climb',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _rows.removeAt(index));
                    _emit();
                  },
                ),
              ],
            ),
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
          ..._timers(
            '${widget.block.blockId}-${prescription.rowId}',
            prescription.workSeconds,
            prescription.restSeconds,
          ),
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
        if (!row.isLegacy)
          Text(
              '${row.grade} · ${row.attempts} attempts · ${row.sent! ? 'Sent' : 'Not sent'}'
              '${row.notes == null || row.notes!.isEmpty ? '' : ' · ${row.notes}'}'),
      if (actual?.rpe != null) Text('RPE ${actual!.rpe}'),
      if (actual?.notes != null) Text('Climbing note: ${actual!.notes}'),
      if (actual == null) const Text('No result recorded'),
    ];
  }

  List<Widget> _timers(String scope, int? workSeconds, int? restSeconds) => [
        if (workSeconds != null)
          widget.recordingEnabled
              ? WorkoutTimerWidget(
                  key: ValueKey('climbing-work-timer-$scope'),
                  label: 'Work',
                  targetSeconds: workSeconds,
                )
              : Text('Work: ${workSeconds}s'),
        if (restSeconds != null)
          widget.recordingEnabled
              ? WorkoutTimerWidget(
                  key: ValueKey('climbing-rest-timer-$scope'),
                  label: 'Rest',
                  targetSeconds: restSeconds,
                )
              : Text('Rest: ${restSeconds}s'),
      ];
}
