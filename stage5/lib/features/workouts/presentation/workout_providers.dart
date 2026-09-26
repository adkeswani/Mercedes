import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

/// Singleton repository for workout templates.
final workoutTemplateRepositoryProvider = Provider<WorkoutTemplateRepository>((
  ref,
) {
  return WorkoutTemplateRepository();
});

/// Streams all non-deleted workout templates for the current user.
final workoutTemplatesProvider = StreamProvider<List<WorkoutTemplate>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(workoutTemplateRepositoryProvider);
  return repo.watchAll(user.uid);
});

/// A workout exposed through the latest published version of a program.
class ProgramWorkoutOption {
  const ProgramWorkoutOption({required this.template, required this.version});

  final WorkoutTemplate template;
  final int version;
}

/// Loads the distinct workouts available through a program's latest version.
///
/// Unlike [workoutTemplatesProvider], this is not creator-scoped: enrolled
/// athletes can read referenced shared templates and schedule them for
/// themselves.
final programWorkoutOptionsProvider =
    FutureProvider.family<List<ProgramWorkoutOption>, String>((
  ref,
  programId,
) async {
  final programRepo = ref.watch(programRepositoryProvider);
  final workoutRepo = ref.watch(workoutTemplateRepositoryProvider);
  final entries = await programRepo.getLatestEntries(programId);
  final seen = <String>{};
  final options = <ProgramWorkoutOption>[];

  for (final entry in entries) {
    if (!seen.add(entry.workoutTemplateId)) continue;
    final template = await workoutRepo.getById(entry.workoutTemplateId);
    if (template == null) continue;
    options.add(
      ProgramWorkoutOption(
        template: template,
        version: entry.workoutTemplateVersion,
      ),
    );
  }
  options.sort(
    (a, b) => a.template.name.toLowerCase().compareTo(
          b.template.name.toLowerCase(),
        ),
  );
  return options;
});

/// Local draft state for the workout builder.
///
/// Holds typed workout blocks being edited before publishing.
/// Reset when entering the builder, persisted only on publish.
class WorkoutDraftNotifier extends StateNotifier<List<WorkoutBlock>> {
  WorkoutDraftNotifier({String Function(String prefix)? idGenerator})
      : _idGenerator = idGenerator ?? _defaultBuilderId,
        super([]);

  final String Function(String prefix) _idGenerator;
  List<WorkoutBlock>? _undoState;
  bool _isDirty = false;
  int _revision = 0;

  bool get canUndo => _undoState != null;
  bool get isDirty => _isDirty;
  int get revision => _revision;

  static var _sequence = 0;
  static String _defaultBuilderId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  void load(List<WorkoutBlock> blocks) {
    _validateUniqueIds(blocks);
    state = _normalizeBlocks(blocks);
    _undoState = null;
    _isDirty = false;
    _revision++;
  }

  void addExercise({
    required ExerciseSlot slot,
    String? blockId,
    int? index,
    String? targetBlockId,
  }) {
    if (targetBlockId != null) {
      addExerciseToBlock(
        targetBlockId: targetBlockId,
        slot: slot,
        index: index,
      );
      return;
    }
    _ensureCapacity(additionalSlots: 1, additionalBlocks: 1);
    _ensureNewSlotId(slot.slotId);
    final resolvedBlockId = blockId ?? _idGenerator('block');
    _ensureNewBlockId(resolvedBlockId);
    final insertionIndex = index ?? state.length;
    _checkInsertionIndex(insertionIndex, state.length);
    final updated = List<WorkoutBlock>.of(state)
      ..insert(
        insertionIndex,
        StandardExerciseBlock(
          blockId: resolvedBlockId,
          sortOrder: insertionIndex,
          exercise: slot.copyWith(sortOrder: 0),
        ),
      );
    _commit(_normalizeBlocks(updated));
  }

  void addLibraryExercise({
    required String exerciseId,
    required int exerciseVersion,
    required String exerciseName,
    int? index,
    String? targetBlockId,
    ExerciseMode mode = ExerciseMode.reps,
  }) {
    addExercise(
      blockId: targetBlockId == null ? _idGenerator('block') : null,
      index: index,
      targetBlockId: targetBlockId,
      slot: ExerciseSlot(
        slotId: _idGenerator('slot'),
        exerciseId: exerciseId,
        exerciseVersion: exerciseVersion,
        exerciseName: exerciseName,
        sortOrder: 0,
        mode: mode,
        sets: mode == ExerciseMode.reps ? 3 : null,
        reps: mode == ExerciseMode.reps ? '8-12' : null,
        durationSeconds: mode == ExerciseMode.time ? 30 : null,
      ),
    );
  }

  void addExerciseToBlock({
    required String targetBlockId,
    required ExerciseSlot slot,
    int? index,
  }) {
    _ensureCapacity(additionalSlots: 1);
    _ensureNewSlotId(slot.slotId);
    final blockIndex = state.indexWhere(
      (block) => block.blockId == targetBlockId,
    );
    if (blockIndex < 0) throw StateError('Target workout block was not found');
    final block = state[blockIndex];
    if (block is StandardExerciseBlock || block is ClimbingRouteBlock) {
      throw StateError('${block.type.name} blocks accept exactly one slot');
    }
    final insertionIndex = index ?? block.slots.length;
    _checkInsertionIndex(insertionIndex, block.slots.length);
    final slots = List<ExerciseSlot>.of(block.slots)
      ..insert(insertionIndex, slot);
    final updated = List<WorkoutBlock>.of(state);
    updated[blockIndex] = _copyBlockWithSlots(block, _normalizeSlots(slots));
    _commit(updated);
  }

  void addTypedBlock({
    required WorkoutBlockType type,
    required ExerciseSlot initialSlot,
    String? blockId,
    int? index,
  }) {
    if (type == WorkoutBlockType.standardExercise) {
      addExercise(slot: initialSlot, blockId: blockId, index: index);
      return;
    }
    _ensureCapacity(additionalSlots: 1, additionalBlocks: 1);
    _ensureNewSlotId(initialSlot.slotId);
    final resolvedBlockId = blockId ?? _idGenerator('block');
    _ensureNewBlockId(resolvedBlockId);
    final insertionIndex = index ?? state.length;
    _checkInsertionIndex(insertionIndex, state.length);
    final slot = initialSlot.copyWith(sortOrder: 0);
    final block = switch (type) {
      WorkoutBlockType.timedInterval => TimedIntervalBlock(
          blockId: resolvedBlockId,
          sortOrder: insertionIndex,
          slots: [slot],
          rounds: 4,
          workSeconds: 30,
          restSeconds: 30,
          title: 'Timed interval',
        ),
      WorkoutBlockType.circuit => CircuitBlock(
          blockId: resolvedBlockId,
          sortOrder: insertionIndex,
          slots: [slot],
          rounds: 3,
          title: 'Circuit',
        ),
      WorkoutBlockType.climbingRoute => ClimbingRouteBlock(
          blockId: resolvedBlockId,
          sortOrder: insertionIndex,
          route: slot,
          grade: 'V0',
          color: 'Unspecified',
          title: 'Climbing route',
        ),
      WorkoutBlockType.standardExercise => throw StateError('Unreachable'),
    };
    final updated = List<WorkoutBlock>.of(state)..insert(insertionIndex, block);
    _commit(_normalizeBlocks(updated));
  }

  void removeAt(int index) {
    _checkExistingIndex(index, state.length);
    final updated = List.of(state);
    updated.removeAt(index);
    _commit(_normalizeBlocks(updated));
  }

  void updateExerciseAt(int index, ExerciseSlot slot) {
    _checkExistingIndex(index, state.length);
    final updated = List.of(state);
    final block = updated[index];
    if (block is! StandardExerciseBlock) {
      throw StateError('Only standard exercise blocks are editable here');
    }
    updated[index] = StandardExerciseBlock(
      blockId: block.blockId,
      sortOrder: block.sortOrder,
      exercise: slot.copyWith(sortOrder: 0),
      title: block.title,
      notes: block.notes,
    );
    _commit(updated);
  }

  void reorder(int oldIndex, int newIndex) {
    _checkExistingIndex(oldIndex, state.length);
    if (newIndex < 0 || newIndex > state.length) {
      throw RangeError.range(newIndex, 0, state.length, 'newIndex');
    }
    final updated = List.of(state);
    if (newIndex > oldIndex) newIndex--;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    _commit(_normalizeBlocks(updated));
  }

  void moveUp(int index) {
    if (index <= 0 || index >= state.length) return;
    reorder(index, index - 1);
  }

  void moveDown(int index) {
    if (index < 0 || index >= state.length - 1) return;
    reorder(index, index + 2);
  }

  void duplicateAt(int index) {
    _checkExistingIndex(index, state.length);
    final source = state[index];
    _ensureCapacity(additionalBlocks: 1, additionalSlots: source.slots.length);
    final slots = [
      for (final slot in source.slots)
        slot.copyWith(slotId: _idGenerator('slot')),
    ];
    final duplicate = _copyBlockWithIdentity(
      source,
      blockId: _idGenerator('block'),
      sortOrder: index + 1,
      slots: _normalizeSlots(slots),
    );
    final updated = List<WorkoutBlock>.of(state)..insert(index + 1, duplicate);
    _commit(_normalizeBlocks(updated));
  }

  void reorderSlot({
    required String blockId,
    required int oldIndex,
    required int newIndex,
  }) {
    final blockIndex = state.indexWhere((block) => block.blockId == blockId);
    if (blockIndex < 0) throw StateError('Workout block was not found');
    final block = state[blockIndex];
    if (block is StandardExerciseBlock || block is ClimbingRouteBlock) {
      throw StateError('${block.type.name} slots cannot be reordered');
    }
    _checkExistingIndex(oldIndex, block.slots.length);
    if (newIndex < 0 || newIndex > block.slots.length) {
      throw RangeError.range(newIndex, 0, block.slots.length, 'newIndex');
    }
    final slots = List<ExerciseSlot>.of(block.slots);
    if (newIndex > oldIndex) newIndex--;
    final slot = slots.removeAt(oldIndex);
    slots.insert(newIndex, slot);
    final updated = List<WorkoutBlock>.of(state);
    updated[blockIndex] = _copyBlockWithSlots(block, _normalizeSlots(slots));
    _commit(updated);
  }

  void undo() {
    final previous = _undoState;
    if (previous == null) return;
    state = previous;
    _undoState = null;
    _isDirty = true;
    _revision++;
  }

  void markSaved() {
    _undoState = null;
    _isDirty = false;
  }

  void clear() {
    state = [];
    _undoState = null;
    _isDirty = false;
    _revision++;
  }

  void _commit(List<WorkoutBlock> blocks) {
    _validateUniqueIds(blocks);
    _undoState = state;
    state = blocks;
    _isDirty = true;
    _revision++;
  }

  void _ensureCapacity({int additionalSlots = 0, int additionalBlocks = 0}) {
    final slotCount = state.fold<int>(
      0,
      (count, block) => count + block.slots.length,
    );
    if (slotCount + additionalSlots > maxExerciseSlotsPerWorkoutVersion) {
      throw StateError(
        'A workout supports at most $maxExerciseSlotsPerWorkoutVersion slots',
      );
    }
    if (state.length + additionalBlocks > maxWorkoutBlocksPerVersion) {
      throw StateError(
        'A workout supports at most $maxWorkoutBlocksPerVersion blocks',
      );
    }
  }

  void _ensureNewSlotId(String slotId) {
    if (state.any(
      (block) => block.slots.any((slot) => slot.slotId == slotId),
    )) {
      throw StateError('Exercise slot ID $slotId already exists');
    }
  }

  void _ensureNewBlockId(String blockId) {
    if (state.any((block) => block.blockId == blockId)) {
      throw StateError('Workout block ID $blockId already exists');
    }
  }

  static void _checkExistingIndex(int index, int length) {
    if (index < 0 || index >= length) {
      throw RangeError.index(index, List<void>.filled(length, null));
    }
  }

  static void _checkInsertionIndex(int index, int length) {
    if (index < 0 || index > length) {
      throw RangeError.range(index, 0, length, 'index');
    }
  }

  static List<ExerciseSlot> _normalizeSlots(List<ExerciseSlot> slots) => [
        for (var index = 0; index < slots.length; index++)
          slots[index].copyWith(sortOrder: index),
      ];

  static List<WorkoutBlock> _normalizeBlocks(List<WorkoutBlock> blocks) => [
        for (var index = 0; index < blocks.length; index++)
          blocks[index].copyWithSortOrder(index),
      ];

  static void _validateUniqueIds(List<WorkoutBlock> blocks) {
    final blockIds = <String>{};
    final slotIds = <String>{};
    for (final block in blocks) {
      if (!blockIds.add(block.blockId)) {
        throw StateError('Duplicate workout block ID ${block.blockId}');
      }
      for (final slot in block.slots) {
        if (!slotIds.add(slot.slotId)) {
          throw StateError('Duplicate exercise slot ID ${slot.slotId}');
        }
      }
    }
  }

  static WorkoutBlock _copyBlockWithSlots(
    WorkoutBlock block,
    List<ExerciseSlot> slots,
  ) =>
      _copyBlockWithIdentity(
        block,
        blockId: block.blockId,
        sortOrder: block.sortOrder,
        slots: slots,
      );

  static WorkoutBlock _copyBlockWithIdentity(
    WorkoutBlock block, {
    required String blockId,
    required int sortOrder,
    required List<ExerciseSlot> slots,
  }) {
    return switch (block) {
      StandardExerciseBlock() => StandardExerciseBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          exercise: slots.single,
          title: block.title,
          notes: block.notes,
        ),
      TimedIntervalBlock() => TimedIntervalBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          slots: slots,
          rounds: block.rounds,
          workSeconds: block.workSeconds,
          restSeconds: block.restSeconds,
          title: block.title,
          notes: block.notes,
        ),
      CircuitBlock() => CircuitBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          slots: slots,
          rounds: block.rounds,
          restBetweenRoundsSeconds: block.restBetweenRoundsSeconds,
          title: block.title,
          notes: block.notes,
        ),
      ClimbingRouteBlock() => ClimbingRouteBlock(
          blockId: blockId,
          sortOrder: sortOrder,
          route: slots.single,
          grade: block.grade,
          color: block.color,
          targetAttempts: block.targetAttempts,
          title: block.title,
          notes: block.notes,
        ),
    };
  }
}

/// Provider for the workout builder draft state.
final workoutDraftProvider =
    StateNotifierProvider<WorkoutDraftNotifier, List<WorkoutBlock>>((ref) {
  return WorkoutDraftNotifier();
});
