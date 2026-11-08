import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';

Map<String, dynamic> initialClimbingInput(WorkoutBlock block) => {
      'climbingType': block.type.name,
      'notes': '',
      'rpe': null,
      if (block is ClimbingCircuitBlock)
        'circuitRows': [
          for (final row in block.rows)
            {'rowId': row.rowId, 'completed': false, 'notes': '', 'rpe': null},
        ],
      if (block is FreeClimbingBlock) 'freeRows': <Map<String, dynamic>>[],
    };

// Incomplete number text is preserved for recovery and validated on submission.
void validateClimbingInput(Map<String, dynamic> input) {
  final type = input['climbingType'];
  if (type != 'climbingCircuit' && type != 'freeClimbing') {
    throw const FormatException('Unknown climbing draft type');
  }
  final key = type == 'climbingCircuit' ? 'circuitRows' : 'freeRows';
  if (input.keys.toSet().difference(
        {'climbingType', 'notes', 'rpe', key, 'rowIds'},
      ).isNotEmpty ||
      input['notes'] is! String ||
      (input['notes'] as String).length > 4000 ||
      (input['rpe'] != null && input['rpe'] is! int)) {
    throw const FormatException('Invalid climbing draft fields');
  }
  validateClimbingRpe(input['rpe'] as int?);
  if (type == 'climbingCircuit' && input['rpe'] != null) {
    throw const FormatException('Circuit RPE belongs to each row');
  }
  final rows = input[key];
  if (rows is! List ||
      rows.length > maxClimbingRows ||
      (type == 'climbingCircuit' && rows.isEmpty)) {
    throw const FormatException('Invalid climbing draft rows');
  }
  final ids = <String>{};
  for (final raw in rows) {
    if (raw is! Map || raw['rowId'] is! String || raw['notes'] is! String) {
      throw const FormatException('Invalid climbing draft row');
    }
    final row = Map<String, dynamic>.from(raw);
    validateClimbingRowId(row['rowId'] as String);
    validateClimbingNote(row['notes'] as String);
    if (!ids.add(row['rowId'] as String)) {
      throw const FormatException('Duplicate climbing draft row ID');
    }
    if (type == 'climbingCircuit') {
      ClimbingCircuitResultRow.fromMap(row);
    } else {
      final legacy = row.containsKey('climbs');
      if (row.keys.toSet().difference({
            'rowId',
            'gradingSystem',
            'grade',
            if (legacy) 'climbs' else ...{'attempts', 'sent'},
            'notes',
          }).isNotEmpty ||
          row[legacy ? 'climbs' : 'attempts'] is! String ||
          (row[legacy ? 'climbs' : 'attempts'] as String).length > 20 ||
          (!legacy && row['sent'] is! bool) ||
          row['grade'] is! String) {
        throw const FormatException('Invalid free climbing draft fields');
      }
      validateClimbingGrade(
        parseGradingSystem(row['gradingSystem']),
        row['grade'] as String,
      );
    }
  }
  if (input.containsKey('rowIds')) {
    validateClimbingRowManifest(input['rowIds'], ids.toList());
  }
}

Map<String, dynamic> climbingInputForStorage(Map<String, dynamic> input) {
  validateClimbingInput(input);
  final circuit = input.containsKey('circuitRows');
  // Legacy counts cannot be converted into individual climbs or attempts.
  final rows = [
    for (final row in (input[circuit ? 'circuitRows' : 'freeRows']) as List)
      if (circuit || !(row as Map).containsKey('climbs'))
        Map<String, dynamic>.from(row as Map),
  ];
  return {
    ...input,
    circuit ? 'circuitRows' : 'freeRows': rows,
    'rowIds': [for (final row in rows) row['rowId']],
  };
}

void validateClimbingInputForBlock(
  WorkoutBlock block,
  Map<String, dynamic> input,
) {
  validateClimbingInput(input);
  if (input['climbingType'] != block.type.name) {
    throw const FormatException(
      'Recovered climbing type does not match the pinned workout',
    );
  }
  if (block is ClimbingCircuitBlock) {
    final rows = input['circuitRows'] as List;
    if (rows.length != block.rows.length) {
      throw const FormatException(
        'Recovered climbing row count does not match the pinned workout',
      );
    }
    for (var i = 0; i < rows.length; i++) {
      if ((rows[i] as Map)['rowId'] != block.rows[i].rowId) {
        throw const FormatException(
          'Recovered climbing rows do not match the pinned workout',
        );
      }
    }
  }
}

ExerciseActual climbingActualFromInput(
  WorkoutBlock block,
  Map<String, dynamic> input,
) {
  validateClimbingInput(input);
  final slot = block.slots.single;
  final actual = ExerciseActual(
    slotId: slot.slotId,
    exerciseId: slot.exerciseId,
    mode: slot.mode,
    climbingType: input['climbingType'] as String,
    rpe: input['rpe'] as int?,
    notes: (input['notes'] as String).trim().isEmpty
        ? null
        : (input['notes'] as String).trim(),
    circuitRows: input['circuitRows'] == null
        ? null
        : (input['circuitRows'] as List)
            .map(
              (r) => ClimbingCircuitResultRow.fromMap(
                Map<String, dynamic>.from(r as Map),
              ),
            )
            .toList(),
    freeRows: input['freeRows'] == null
        ? null
        : (climbingInputForStorage(input)['freeRows'] as List).map((raw) {
            final row = Map<String, dynamic>.from(raw as Map);
            final attempts = int.tryParse((row['attempts'] as String).trim());
            if (attempts == null || attempts < 1) {
              throw ArgumentError(
                'Enter a positive whole number of attempts for ${row['grade']}',
              );
            }
            return FreeClimbingResultRow.fromMap(
              {...row, 'attempts': attempts},
            );
          }).toList(),
  );
  actual.validateForBlock(block);
  return actual;
}
