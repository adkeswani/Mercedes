import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/workouts/data/workout_draft_local_store.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

enum WorkoutDraftSaveStatus { saved, offline, conflict }

class WorkoutDraftSaveResult {
  const WorkoutDraftSaveResult(this.status, {this.authoritativeDraft});

  final WorkoutDraftSaveStatus status;
  final WorkoutCompletionDraft? authoritativeDraft;
}

class WorkoutDraftSaveAttemptDecision {
  const WorkoutDraftSaveAttemptDecision({
    required this.shouldWrite,
    required this.result,
  });

  final bool shouldWrite;
  final WorkoutDraftSaveResult result;
}

WorkoutDraftSaveAttemptDecision decideWorkoutDraftSaveAttempt({
  required WorkoutCompletionDraft draft,
  required WorkoutCompletionDraft? server,
}) {
  if (server == null || server.revision < draft.revision) {
    return const WorkoutDraftSaveAttemptDecision(
      shouldWrite: true,
      result: WorkoutDraftSaveResult(WorkoutDraftSaveStatus.saved),
    );
  }
  final conflict = server.clientId != draft.clientId;
  return WorkoutDraftSaveAttemptDecision(
    shouldWrite: false,
    result: WorkoutDraftSaveResult(
      conflict ? WorkoutDraftSaveStatus.conflict : WorkoutDraftSaveStatus.saved,
      authoritativeDraft: server,
    ),
  );
}

class WorkoutCompletionDraftRepository {
  WorkoutCompletionDraftRepository({
    FirebaseFirestore? firestore,
    WorkoutDraftLocalStore? localStore,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _localStore = localStore ?? createWorkoutDraftLocalStore();

  final FirebaseFirestore _firestore;
  final WorkoutDraftLocalStore _localStore;

  DocumentReference<Map<String, dynamic>> _instance(String instanceId) =>
      _firestore.collection('workoutInstances').doc(instanceId);

  DocumentReference<Map<String, dynamic>> _draft(String instanceId) =>
      _instance(instanceId).collection('completionDrafts').doc('current');

  Future<WorkoutDraftRestoreResult> load({
    required String instanceId,
    required String athleteId,
    required String currentClientId,
  }) async {
    if (currentClientId.isEmpty) {
      throw StateError('A workout draft client ID is required');
    }
    WorkoutCompletionDraft? local;
    var invalidLocal = false;
    try {
      local = await _localStore.read(instanceId);
      if (local != null) {
        _verifyIdentity(local, instanceId, athleteId);
      }
    } on FormatException {
      invalidLocal = true;
      await _localStore.delete(instanceId);
      local = null;
    } on StateError {
      invalidLocal = true;
      await _localStore.delete(instanceId);
      local = null;
    }

    try {
      final instance = await _instance(instanceId).get();
      _verifyInstance(instance, instanceId, athleteId);
    } on FirebaseException {
      if (local != null) {
        return WorkoutDraftRestoreResult(
          kind: WorkoutDraftRestoreKind.local,
          draft: local,
          message: 'Restored offline progress saved on this device.',
          deviceOnly: true,
        );
      }
      rethrow;
    }

    WorkoutCompletionDraft? server;
    try {
      final snapshot = await _draft(instanceId).get();
      if (snapshot.exists && snapshot.data() != null) {
        server = WorkoutCompletionDraft.fromMap(snapshot.data()!);
        _verifyIdentity(server, instanceId, athleteId);
      }
    } on FirebaseException {
      if (local != null) {
        return WorkoutDraftRestoreResult(
          kind: WorkoutDraftRestoreKind.local,
          draft: local,
          message: 'Restored offline progress saved on this device.',
          deviceOnly: true,
        );
      }
      rethrow;
    }

    final result = reconcileWorkoutDrafts(
      local: local,
      server: server,
      currentClientId: currentClientId,
    );
    final selected = result.draft;
    if (selected != null &&
        (local == null || compareWorkoutDrafts(selected, local) != 0)) {
      await _localStore.write(selected);
    }
    if (invalidLocal) {
      return WorkoutDraftRestoreResult(
        kind: WorkoutDraftRestoreKind.invalidLocal,
        draft: selected,
        message: selected == null
            ? 'An invalid saved draft was removed for your safety.'
            : 'An invalid device draft was removed; server progress was restored.',
      );
    }
    if (local != null &&
        (server == null || compareWorkoutDrafts(local, server) > 0)) {
      final synchronized = await save(local);
      if (synchronized.status == WorkoutDraftSaveStatus.conflict &&
          synchronized.authoritativeDraft != null) {
        return WorkoutDraftRestoreResult(
          kind: WorkoutDraftRestoreKind.conflict,
          draft: synchronized.authoritativeDraft,
          message:
              'Another tab saved newer progress while this draft was restored.',
        );
      }
      final authoritative = synchronized.authoritativeDraft;
      if (synchronized.status == WorkoutDraftSaveStatus.saved &&
          authoritative != null &&
          authoritative.clientId == currentClientId &&
          compareWorkoutDrafts(authoritative, local) > 0) {
        return WorkoutDraftRestoreResult(
          kind: WorkoutDraftRestoreKind.server,
          draft: authoritative,
          message: 'Restored saved workout progress.',
        );
      }
      return WorkoutDraftRestoreResult(
        kind: WorkoutDraftRestoreKind.local,
        draft: local,
        message: synchronized.status == WorkoutDraftSaveStatus.offline
            ? 'Restored offline progress saved on this device.'
            : 'Restored device progress and synced it.',
        deviceOnly: synchronized.status == WorkoutDraftSaveStatus.offline,
      );
    }
    return result;
  }

  Future<WorkoutDraftSaveResult> save(
    WorkoutCompletionDraft draft,
  ) async {
    draft.validate();
    await _localStore.write(draft);
    try {
      final result = await _firestore.runTransaction<WorkoutDraftSaveResult>((
        transaction,
      ) async {
        final instanceSnapshot = await transaction.get(
          _instance(draft.instanceId),
        );
        _verifyInstance(
          instanceSnapshot,
          draft.instanceId,
          draft.athleteId,
        );
        final draftRef = _draft(draft.instanceId);
        final serverSnapshot = await transaction.get(draftRef);
        WorkoutCompletionDraft? server;
        if (serverSnapshot.exists && serverSnapshot.data() != null) {
          server = WorkoutCompletionDraft.fromMap(serverSnapshot.data()!);
          _verifyIdentity(server, draft.instanceId, draft.athleteId);
        }
        final decision = decideWorkoutDraftSaveAttempt(
          draft: draft,
          server: server,
        );
        assert(() {
          // ignore: avoid_print
          print(
            'WORKOUT_DRAFT_SAVE_ATTEMPT'
            '|draftRevision=${draft.revision}'
            '|serverRevision=${server?.revision ?? 0}'
            '|sameClient=${server == null || server.clientId == draft.clientId}'
            '|shouldWrite=${decision.shouldWrite}'
            '|status=${decision.result.status.name}',
          );
          return true;
        }());
        if (!decision.shouldWrite) {
          return decision.result;
        }
        transaction.set(draftRef, draft.toMap(includeServerTimestamp: true));
        return decision.result;
      });
      final authoritative = result.authoritativeDraft;
      if (authoritative != null) {
        await _localStore.write(authoritative);
      }
      return result;
    } on FirebaseException {
      return const WorkoutDraftSaveResult(WorkoutDraftSaveStatus.offline);
    }
  }

  Future<void> clearLocal({
    required String instanceId,
    required String athleteId,
  }) async {
    final local = await _localStore.read(instanceId);
    if (local != null) {
      _verifyIdentity(local, instanceId, athleteId);
    }
    await _localStore.delete(instanceId);
  }

  Future<void> clearLocalAfterCompletion({
    required String instanceId,
    required String athleteId,
  }) async {
    final snapshot = await _instance(instanceId).get();
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Instance $instanceId not found');
    }
    final data = snapshot.data()!;
    if (data['athleteId'] != athleteId) {
      throw StateError('User $athleteId does not own instance $instanceId');
    }
    if (data['status'] != 'completed') {
      throw StateError('Instance $instanceId must be completed');
    }
    await _localStore.delete(instanceId);
  }

  void _verifyInstance(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    String instanceId,
    String athleteId,
  ) {
    if (!snapshot.exists || snapshot.data() == null) {
      throw StateError('Instance $instanceId not found');
    }
    final data = snapshot.data()!;
    if (data['athleteId'] != athleteId) {
      throw StateError('User $athleteId does not own instance $instanceId');
    }
    if (data['status'] != 'scheduled') {
      throw StateError('Instance $instanceId must be scheduled');
    }
  }

  void _verifyIdentity(
    WorkoutCompletionDraft draft,
    String instanceId,
    String athleteId,
  ) {
    if (draft.instanceId != instanceId || draft.athleteId != athleteId) {
      throw StateError('Workout draft identity does not match');
    }
  }
}
