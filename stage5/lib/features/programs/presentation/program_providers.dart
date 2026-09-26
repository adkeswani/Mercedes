import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/data/program_folder_repository.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/program.dart';

/// Singleton repository for programs.
final programRepositoryProvider = Provider<ProgramRepository>((ref) {
  return ProgramRepository();
});

/// Singleton repository for program folders.
final programFolderRepositoryProvider = Provider<ProgramFolderRepository>((
  ref,
) {
  return ProgramFolderRepository();
});

/// Streams all non-deleted programs for the current user.
final programsProvider = StreamProvider<List<Program>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(programRepositoryProvider);
  return repo.watchAll(user.uid);
});

/// Streams the current user's program folders.
final programFoldersProvider = StreamProvider<List<ProgramFolder>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const Stream.empty();
  final repo = ref.watch(programFolderRepositoryProvider);
  return repo.watchFolders(user.uid);
});

class ProgramDraftState {
  const ProgramDraftState({
    this.entries = const [],
    this.phases = const [],
    this.isDirty = false,
    this.canUndo = false,
  });

  final List<ProgramScheduleEntry> entries;
  final List<ProgramPhase> phases;
  final bool isDirty;
  final bool canUndo;

  ProgramDraftState copyWith({
    List<ProgramScheduleEntry>? entries,
    List<ProgramPhase>? phases,
    bool? isDirty,
    bool? canUndo,
  }) {
    return ProgramDraftState(
      entries: entries ?? this.entries,
      phases: phases ?? this.phases,
      isDirty: isDirty ?? this.isDirty,
      canUndo: canUndo ?? this.canUndo,
    );
  }
}

class ProgramDraftNotifier extends StateNotifier<ProgramDraftState> {
  ProgramDraftNotifier({String Function(String prefix)? idGenerator})
      : _idGenerator = idGenerator ?? _defaultBuilderId,
        super(const ProgramDraftState());

  final String Function(String prefix) _idGenerator;
  ProgramDraftState? _undoState;
  int _revision = 0;

  int get revision => _revision;

  static var _sequence = 0;
  static String _defaultBuilderId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  void load(
    List<ProgramScheduleEntry> entries, {
    List<ProgramPhase> phases = const [],
  }) {
    final normalizedEntries = [
      for (var index = 0; index < entries.length; index++)
        entries[index].copyWith(
          entryId: entries[index].resolvedEntryId,
          sortOrder: index,
        ),
    ];
    final normalizedPhases = _normalizePhases(phases);
    _validate(normalizedEntries, normalizedPhases);
    _undoState = null;
    state = ProgramDraftState(
      entries: normalizedEntries,
      phases: normalizedPhases,
    );
    _revision++;
  }

  void addWorkout(ProgramScheduleEntry entry, {int? index, String? phaseId}) {
    _requirePhase(phaseId);
    final insertionIndex = index ?? state.entries.length;
    _checkInsertionIndex(insertionIndex, state.entries.length);
    var stable = entry.copyWith(
      entryId: entry.entryId ?? _idGenerator('entry'),
      phaseId: phaseId,
      clearPhase: phaseId == null,
    );
    if (state.entries.any((item) => item.resolvedEntryId == stable.entryId)) {
      throw StateError('Program entry ID ${stable.entryId} already exists');
    }
    stable = stable.copyWith(sortOrder: insertionIndex);
    final entries = List<ProgramScheduleEntry>.of(state.entries)
      ..insert(insertionIndex, stable);
    _commit(entries: _normalizeEntries(entries));
  }

  void duplicateAt(int index) {
    _checkExistingIndex(index, state.entries.length);
    final source = state.entries[index];
    addWorkout(
      source.copyWith(entryId: _idGenerator('entry')),
      index: index + 1,
      phaseId: source.phaseId,
    );
  }

  void removeAt(int index) {
    _checkExistingIndex(index, state.entries.length);
    final entries = List<ProgramScheduleEntry>.of(state.entries)
      ..removeAt(index);
    _commit(entries: _normalizeEntries(entries));
  }

  void reorder(int oldIndex, int newIndex) {
    _checkExistingIndex(oldIndex, state.entries.length);
    if (newIndex < 0 || newIndex > state.entries.length) {
      throw RangeError.range(newIndex, 0, state.entries.length, 'newIndex');
    }
    final entries = List<ProgramScheduleEntry>.of(state.entries);
    if (newIndex > oldIndex) newIndex--;
    final item = entries.removeAt(oldIndex);
    entries.insert(newIndex, item);
    _commit(entries: _normalizeEntries(entries));
  }

  void moveUp(int index) {
    if (index <= 0 || index >= state.entries.length) return;
    reorder(index, index - 1);
  }

  void moveDown(int index) {
    if (index < 0 || index >= state.entries.length - 1) return;
    reorder(index, index + 2);
  }

  void moveEntryToPhase({
    required String entryId,
    required String? phaseId,
    int? index,
  }) {
    _requirePhase(phaseId);
    final oldIndex = state.entries.indexWhere(
      (entry) => entry.resolvedEntryId == entryId,
    );
    if (oldIndex < 0) throw StateError('Program entry was not found');
    final entries = List<ProgramScheduleEntry>.of(state.entries);
    final moved = entries
        .removeAt(oldIndex)
        .copyWith(phaseId: phaseId, clearPhase: phaseId == null);
    final insertionIndex = index ?? entries.length;
    _checkInsertionIndex(insertionIndex, entries.length);
    entries.insert(insertionIndex, moved);
    _commit(entries: _normalizeEntries(entries));
  }

  void setDayOffset(int index, int dayOffset) {
    if (index < 0 || index >= state.entries.length || dayOffset < 0) return;
    final entries = List<ProgramScheduleEntry>.of(state.entries);
    entries[index] = entries[index].copyWith(dayOffset: dayOffset);
    _commit(entries: entries);
  }

  void addAll(List<ProgramScheduleEntry> entries, {String? phaseId}) {
    for (final entry in entries) {
      addWorkout(entry, phaseId: phaseId);
    }
  }

  void addPhase(String name, {String? phaseId, int? index}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Phase name cannot be empty');
    final resolvedId = phaseId ?? _idGenerator('phase');
    if (state.phases.any((phase) => phase.phaseId == resolvedId)) {
      throw StateError('Program phase ID $resolvedId already exists');
    }
    final insertionIndex = index ?? state.phases.length;
    _checkInsertionIndex(insertionIndex, state.phases.length);
    final phases = List<ProgramPhase>.of(state.phases)
      ..insert(
        insertionIndex,
        ProgramPhase(
          phaseId: resolvedId,
          name: trimmed,
          sortOrder: insertionIndex,
        ),
      );
    _commit(phases: _normalizePhases(phases));
  }

  void renamePhase(String phaseId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Phase name cannot be empty');
    final index = state.phases.indexWhere((phase) => phase.phaseId == phaseId);
    if (index < 0) throw StateError('Program phase was not found');
    final phases = List<ProgramPhase>.of(state.phases);
    phases[index] = phases[index].copyWith(name: trimmed);
    _commit(phases: phases);
  }

  void removePhase(String phaseId) {
    final index = state.phases.indexWhere((phase) => phase.phaseId == phaseId);
    if (index < 0) throw StateError('Program phase was not found');
    final fallbackPhaseId = index > 0 ? state.phases[index - 1].phaseId : null;
    final phases = List<ProgramPhase>.of(state.phases)..removeAt(index);
    final entries = [
      for (final entry in state.entries)
        if (entry.phaseId == phaseId)
          entry.copyWith(
            phaseId: fallbackPhaseId,
            clearPhase: fallbackPhaseId == null,
          )
        else
          entry,
    ];
    _commit(entries: entries, phases: _normalizePhases(phases));
  }

  void reorderPhase(int oldIndex, int newIndex) {
    _checkExistingIndex(oldIndex, state.phases.length);
    if (newIndex < 0 || newIndex > state.phases.length) {
      throw RangeError.range(newIndex, 0, state.phases.length, 'newIndex');
    }
    final phases = List<ProgramPhase>.of(state.phases);
    if (newIndex > oldIndex) newIndex--;
    final phase = phases.removeAt(oldIndex);
    phases.insert(newIndex, phase);
    _commit(phases: _normalizePhases(phases));
  }

  void undo() {
    final previous = _undoState;
    if (previous == null) return;
    state = previous.copyWith(isDirty: true, canUndo: false);
    _undoState = null;
    _revision++;
  }

  void markSaved() {
    _undoState = null;
    state = state.copyWith(isDirty: false, canUndo: false);
  }

  void clear() {
    _undoState = null;
    state = const ProgramDraftState();
    _revision++;
  }

  void _commit({
    List<ProgramScheduleEntry>? entries,
    List<ProgramPhase>? phases,
  }) {
    final nextEntries = entries ?? state.entries;
    final nextPhases = phases ?? state.phases;
    _validate(nextEntries, nextPhases);
    _undoState = state;
    state = ProgramDraftState(
      entries: nextEntries,
      phases: nextPhases,
      isDirty: true,
      canUndo: true,
    );
    _revision++;
  }

  void _requirePhase(String? phaseId) {
    if (phaseId != null &&
        !state.phases.any((phase) => phase.phaseId == phaseId)) {
      throw StateError('Program phase $phaseId was not found');
    }
  }

  static List<ProgramScheduleEntry> _normalizeEntries(
    List<ProgramScheduleEntry> entries,
  ) =>
      [
        for (var index = 0; index < entries.length; index++)
          entries[index].copyWith(sortOrder: index),
      ];

  static List<ProgramPhase> _normalizePhases(List<ProgramPhase> phases) => [
        for (var index = 0; index < phases.length; index++)
          phases[index].copyWith(sortOrder: index),
      ];

  static void _validate(
    List<ProgramScheduleEntry> entries,
    List<ProgramPhase> phases,
  ) {
    final entryIds = <String>{};
    for (final entry in entries) {
      entry.validate();
      if (!entryIds.add(entry.resolvedEntryId)) {
        throw StateError('Duplicate program entry ID ${entry.resolvedEntryId}');
      }
    }
    final phaseIds = <String>{};
    for (final phase in phases) {
      phase.validate();
      if (!phaseIds.add(phase.phaseId)) {
        throw StateError('Duplicate program phase ID ${phase.phaseId}');
      }
    }
    for (final entry in entries) {
      if (entry.phaseId != null && !phaseIds.contains(entry.phaseId)) {
        throw StateError(
          'Program entry ${entry.resolvedEntryId} has an unknown phase',
        );
      }
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
}

final programDraftProvider =
    StateNotifierProvider<ProgramDraftNotifier, ProgramDraftState>((ref) {
  return ProgramDraftNotifier();
});
