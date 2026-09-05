import 'package:stage5/core/enums.dart';

const maxWorkoutBlocksPerVersion = 9;
const maxExerciseSlotsPerWorkoutVersion = 9;

enum WorkoutBlockType {
  standardExercise,
  timedInterval,
  circuit,
  climbingRoute,
}

String legacyExerciseSlotId(int sortOrder) => 'legacy-slot-$sortOrder';

String legacyWorkoutBlockId(int sortOrder) => 'legacy-block-$sortOrder';

void _validateStableId(String value, String fieldName) {
  if (value.isEmpty) {
    throw ArgumentError('$fieldName cannot be empty');
  }
  if (value.contains('/')) {
    throw ArgumentError('$fieldName cannot contain "/"');
  }
}

class ExerciseSlot {
  ExerciseSlot({
    required this.exerciseId,
    required this.sortOrder,
    required this.mode,
    String? slotId,
    this.exerciseVersion = 1,
    this.legacyStorageOrder,
    this.exerciseName,
    this.sets,
    this.reps,
    this.durationSeconds,
    this.weight,
    this.restSeconds,
    this.notes,
  }) : slotId = slotId ?? legacyExerciseSlotId(sortOrder);

  final String slotId;
  final String exerciseId;
  final int exerciseVersion;
  final int? legacyStorageOrder;
  final int sortOrder;
  final ExerciseMode mode;
  final String? exerciseName;
  final int? sets;
  final String? reps;
  final int? durationSeconds;
  final String? weight;
  final int? restSeconds;
  final String? notes;

  ExerciseSlot copyWith({
    String? slotId,
    String? exerciseId,
    int? exerciseVersion,
    int? legacyStorageOrder,
    int? sortOrder,
    ExerciseMode? mode,
    String? exerciseName,
    int? sets,
    String? reps,
    int? durationSeconds,
    String? weight,
    int? restSeconds,
    String? notes,
  }) {
    return ExerciseSlot(
      slotId: slotId ?? this.slotId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseVersion: exerciseVersion ?? this.exerciseVersion,
      legacyStorageOrder: legacyStorageOrder ?? this.legacyStorageOrder,
      sortOrder: sortOrder ?? this.sortOrder,
      mode: mode ?? this.mode,
      exerciseName: exerciseName ?? this.exerciseName,
      sets: sets ?? this.sets,
      reps: reps ?? this.reps,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      weight: weight ?? this.weight,
      restSeconds: restSeconds ?? this.restSeconds,
      notes: notes ?? this.notes,
    );
  }

  void validate() {
    _validateStableId(slotId, 'slotId');
    if (exerciseId.isEmpty) {
      throw ArgumentError('exerciseId cannot be empty');
    }
    if (exerciseVersion < 1) {
      throw ArgumentError('exerciseVersion must be >= 1');
    }
    if (legacyStorageOrder != null && legacyStorageOrder! < 0) {
      throw ArgumentError('legacyStorageOrder must be >= 0 when provided');
    }
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
    if (sets != null && sets! < 1) {
      throw ArgumentError('sets must be >= 1 when provided');
    }
    if (durationSeconds != null && durationSeconds! < 1) {
      throw ArgumentError('durationSeconds must be >= 1 when provided');
    }
    if (restSeconds != null && restSeconds! < 0) {
      throw ArgumentError('restSeconds must be >= 0 when provided');
    }
  }
}

@Deprecated('Use ExerciseSlot. Prescriptions are now stable workout slots.')
typedef ExercisePrescription = ExerciseSlot;

sealed class WorkoutBlock {
  const WorkoutBlock({
    required this.blockId,
    required this.sortOrder,
    required this.slots,
    this.title,
    this.notes,
  });

  final String blockId;
  final int sortOrder;
  final List<ExerciseSlot> slots;
  final String? title;
  final String? notes;

  WorkoutBlockType get type;

  WorkoutBlock copyWithSortOrder(int sortOrder);

  void validate() {
    _validateStableId(blockId, 'blockId');
    if (sortOrder < 0) {
      throw ArgumentError('sortOrder must be >= 0');
    }
    if (slots.isEmpty) {
      throw ArgumentError('Workout blocks must contain at least one slot');
    }
    final slotIds = <String>{};
    final slotSortOrders = <int>{};
    for (final slot in slots) {
      slot.validate();
      if (!slotIds.add(slot.slotId)) {
        throw ArgumentError('Exercise slot IDs must be unique within a block');
      }
      if (!slotSortOrders.add(slot.sortOrder)) {
        throw ArgumentError(
          'Exercise slot sortOrder values must be unique within a block',
        );
      }
    }
    for (var index = 0; index < slots.length; index++) {
      if (!slotSortOrders.contains(index)) {
        throw ArgumentError(
          'Exercise slot sortOrder values must be contiguous from 0',
        );
      }
    }
  }
}

class StandardExerciseBlock extends WorkoutBlock {
  StandardExerciseBlock({
    required super.blockId,
    required super.sortOrder,
    required ExerciseSlot exercise,
    super.title,
    super.notes,
  }) : super(slots: [exercise]);

  @override
  WorkoutBlockType get type => WorkoutBlockType.standardExercise;

  ExerciseSlot get exercise => slots.single;

  @override
  StandardExerciseBlock copyWithSortOrder(int sortOrder) {
    return StandardExerciseBlock(
      blockId: blockId,
      sortOrder: sortOrder,
      exercise: exercise,
      title: title,
      notes: notes,
    );
  }

  @override
  void validate() {
    super.validate();
    if (slots.length != 1) {
      throw ArgumentError('Standard exercise blocks require exactly one slot');
    }
  }
}

class TimedIntervalBlock extends WorkoutBlock {
  const TimedIntervalBlock({
    required super.blockId,
    required super.sortOrder,
    required super.slots,
    required this.rounds,
    required this.workSeconds,
    required this.restSeconds,
    super.title,
    super.notes,
  });

  final int rounds;
  final int workSeconds;
  final int restSeconds;

  @override
  WorkoutBlockType get type => WorkoutBlockType.timedInterval;

  @override
  TimedIntervalBlock copyWithSortOrder(int sortOrder) {
    return TimedIntervalBlock(
      blockId: blockId,
      sortOrder: sortOrder,
      slots: slots,
      rounds: rounds,
      workSeconds: workSeconds,
      restSeconds: restSeconds,
      title: title,
      notes: notes,
    );
  }

  @override
  void validate() {
    super.validate();
    if (rounds < 1) throw ArgumentError('rounds must be >= 1');
    if (workSeconds < 1) {
      throw ArgumentError('workSeconds must be >= 1');
    }
    if (restSeconds < 0) {
      throw ArgumentError('restSeconds must be >= 0');
    }
  }
}

class CircuitBlock extends WorkoutBlock {
  const CircuitBlock({
    required super.blockId,
    required super.sortOrder,
    required super.slots,
    required this.rounds,
    this.restBetweenRoundsSeconds = 0,
    super.title,
    super.notes,
  });

  final int rounds;
  final int restBetweenRoundsSeconds;

  @override
  WorkoutBlockType get type => WorkoutBlockType.circuit;

  @override
  CircuitBlock copyWithSortOrder(int sortOrder) {
    return CircuitBlock(
      blockId: blockId,
      sortOrder: sortOrder,
      slots: slots,
      rounds: rounds,
      restBetweenRoundsSeconds: restBetweenRoundsSeconds,
      title: title,
      notes: notes,
    );
  }

  @override
  void validate() {
    super.validate();
    if (rounds < 1) throw ArgumentError('rounds must be >= 1');
    if (restBetweenRoundsSeconds < 0) {
      throw ArgumentError('restBetweenRoundsSeconds must be >= 0');
    }
  }
}

class ClimbingRouteBlock extends WorkoutBlock {
  ClimbingRouteBlock({
    required super.blockId,
    required super.sortOrder,
    required ExerciseSlot route,
    required this.grade,
    required this.color,
    this.targetAttempts,
    super.title,
    super.notes,
  }) : super(slots: [route]);

  final String grade;
  final String color;
  final int? targetAttempts;

  @override
  WorkoutBlockType get type => WorkoutBlockType.climbingRoute;

  ExerciseSlot get route => slots.single;

  @override
  ClimbingRouteBlock copyWithSortOrder(int sortOrder) {
    return ClimbingRouteBlock(
      blockId: blockId,
      sortOrder: sortOrder,
      route: route,
      grade: grade,
      color: color,
      targetAttempts: targetAttempts,
      title: title,
      notes: notes,
    );
  }

  @override
  void validate() {
    super.validate();
    if (slots.length != 1) {
      throw ArgumentError('Climbing route blocks require exactly one slot');
    }
    if (grade.trim().isEmpty) {
      throw ArgumentError('grade cannot be empty');
    }
    if (color.trim().isEmpty) {
      throw ArgumentError('color cannot be empty');
    }
    if (targetAttempts != null && targetAttempts! < 1) {
      throw ArgumentError('targetAttempts must be >= 1 when provided');
    }
  }
}

List<WorkoutBlock> legacyStandardBlocksFromSlots(
  List<ExerciseSlot> slots,
) {
  return [
    for (var index = 0; index < slots.length; index++)
      StandardExerciseBlock(
        blockId: legacyWorkoutBlockId(index),
        sortOrder: index,
        exercise: slots[index].copyWith(
          slotId: slots[index].slotId.isEmpty
              ? legacyExerciseSlotId(index)
              : slots[index].slotId,
          sortOrder: 0,
        ),
      ),
  ];
}
