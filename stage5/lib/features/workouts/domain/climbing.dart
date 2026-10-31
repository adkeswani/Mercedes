enum ClimbingGradingSystem { vScale, yds }

const maxClimbingRows = 9;
const freeClimbingExerciseId = 'builtin-free-climbing';

const vScaleGrades = [
  'VB',
  'V0',
  'V1',
  'V2',
  'V3',
  'V4',
  'V5',
  'V6',
  'V7',
  'V8',
  'V9',
  'V10',
  'V11',
  'V12',
  'V13',
  'V14',
  'V15',
  'V16',
  'V17',
];
const ydsGrades = [
  '5.0',
  '5.1',
  '5.2',
  '5.3',
  '5.4',
  '5.5',
  '5.6',
  '5.7',
  '5.8',
  '5.9',
  '5.10a',
  '5.10b',
  '5.10c',
  '5.10d',
  '5.11a',
  '5.11b',
  '5.11c',
  '5.11d',
  '5.12a',
  '5.12b',
  '5.12c',
  '5.12d',
  '5.13a',
  '5.13b',
  '5.13c',
  '5.13d',
  '5.14a',
  '5.14b',
  '5.14c',
  '5.14d',
  '5.15a',
  '5.15b',
  '5.15c',
  '5.15d',
];

extension ClimbingGrades on ClimbingGradingSystem {
  List<String> get grades => switch (this) {
        ClimbingGradingSystem.vScale => vScaleGrades,
        ClimbingGradingSystem.yds => ydsGrades,
      };
  String get label => switch (this) {
        ClimbingGradingSystem.vScale => 'V-scale (bouldering)',
        ClimbingGradingSystem.yds => 'YDS (rope)',
      };
}

ClimbingGradingSystem parseGradingSystem(Object? value) {
  for (final system in ClimbingGradingSystem.values) {
    if (system.name == value) return system;
  }
  throw const FormatException('Unknown climbing grading system');
}

void validateClimbingGrade(ClimbingGradingSystem system, String grade) {
  if (!system.grades.contains(grade)) {
    throw ArgumentError('Select a canonical ${system.label} grade');
  }
}

void validateClimbingRowId(String rowId) {
  if (rowId.isEmpty || rowId.contains('/')) {
    throw ArgumentError('Climbing row ID must be nonempty and Firestore-safe');
  }
}

void validateClimbingRpe(int? rpe) {
  if (rpe != null && (rpe < 1 || rpe > 10)) {
    throw ArgumentError('RPE must be 1 through 10');
  }
}

void validateClimbingNote(String? note) {
  if (note != null && note.length > 4000) {
    throw ArgumentError('Climbing notes must be at most 4000 characters');
  }
}

void validateClimbingRowManifest(Object? value, List<String> rowIds) {
  if (value is! List || value.length != rowIds.length) {
    throw const FormatException('Climbing row ID manifest is invalid');
  }
  for (var i = 0; i < rowIds.length; i++) {
    if (value[i] != rowIds[i]) {
      throw const FormatException('Climbing row ID manifest is invalid');
    }
  }
}

class ClimbingCircuitRow {
  const ClimbingCircuitRow({
    required this.rowId,
    required this.gradingSystem,
    required this.grade,
    required this.climbs,
    this.maxAttemptsPerClimb,
    this.notes,
  });
  final String rowId;
  final ClimbingGradingSystem gradingSystem;
  final String grade;
  final int climbs;
  final int? maxAttemptsPerClimb;
  final String? notes;

  void validate() {
    validateClimbingRowId(rowId);
    validateClimbingGrade(gradingSystem, grade);
    if (climbs < 1) throw ArgumentError('Number of climbs must be positive');
    if (maxAttemptsPerClimb != null && maxAttemptsPerClimb! < 1) {
      throw ArgumentError('Max attempts per climb must be positive');
    }
    validateClimbingNote(notes);
  }

  Map<String, dynamic> toMap() => {
        'rowId': rowId,
        'gradingSystem': gradingSystem.name,
        'grade': grade,
        'climbs': climbs,
        'maxAttemptsPerClimb': maxAttemptsPerClimb,
        'notes': notes,
      };

  factory ClimbingCircuitRow.fromMap(Map<String, dynamic> map) {
    final row = ClimbingCircuitRow(
      rowId: map['rowId'] as String,
      gradingSystem: parseGradingSystem(map['gradingSystem']),
      grade: map['grade'] as String,
      climbs: map['climbs'] as int,
      maxAttemptsPerClimb: map['maxAttemptsPerClimb'] as int?,
      notes: map['notes'] as String?,
    );
    row.validate();
    return row;
  }
}

class ClimbingCircuitResultRow {
  const ClimbingCircuitResultRow({
    required this.rowId,
    required this.completed,
    this.notes,
    this.rpe,
  });
  final String rowId;
  final bool completed;
  final String? notes;
  final int? rpe;

  void validate() {
    validateClimbingRowId(rowId);
    validateClimbingRpe(rpe);
    validateClimbingNote(notes);
  }

  Map<String, dynamic> toMap() => {
        'rowId': rowId,
        'completed': completed,
        'notes': notes,
        'rpe': rpe,
      };

  factory ClimbingCircuitResultRow.fromMap(Map<String, dynamic> map) {
    if (!map.keys
        .toSet()
        .difference({'rowId', 'completed', 'notes', 'rpe'}).isEmpty) {
      throw const FormatException('Unexpected circuit result fields');
    }
    final row = ClimbingCircuitResultRow(
      rowId: map['rowId'] as String,
      completed: map['completed'] as bool,
      notes: map['notes'] as String?,
      rpe: map['rpe'] as int?,
    );
    row.validate();
    return row;
  }
}

class FreeClimbingResultRow {
  const FreeClimbingResultRow({
    required this.rowId,
    required this.gradingSystem,
    required this.grade,
    required this.climbs,
    this.notes,
  });
  final String rowId;
  final ClimbingGradingSystem gradingSystem;
  final String grade;
  final int climbs;
  final String? notes;

  void validate() {
    validateClimbingRowId(rowId);
    validateClimbingGrade(gradingSystem, grade);
    if (climbs < 1) throw ArgumentError('Climbs completed must be positive');
    validateClimbingNote(notes);
  }

  Map<String, dynamic> toMap() => {
        'rowId': rowId,
        'gradingSystem': gradingSystem.name,
        'grade': grade,
        'climbs': climbs,
        'notes': notes,
      };

  factory FreeClimbingResultRow.fromMap(Map<String, dynamic> map) {
    if (!map.keys.toSet().difference({
      'rowId',
      'gradingSystem',
      'grade',
      'climbs',
      'notes',
    }).isEmpty) {
      throw const FormatException('Unexpected free climbing result fields');
    }
    final row = FreeClimbingResultRow(
      rowId: map['rowId'] as String,
      gradingSystem: parseGradingSystem(map['gradingSystem']),
      grade: map['grade'] as String,
      climbs: map['climbs'] as int,
      notes: map['notes'] as String?,
    );
    row.validate();
    return row;
  }
}
