import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:stage5/features/workouts/data/workout_draft_local_store.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

enum WorkoutDraftSaveStatus { saved, offline, conflict }

class WorkoutDraftSaveResult {
  const WorkoutDraftSaveResult(this.status, {this.authoritativeDraft});

  final WorkoutDraftSaveStatus status;
  final WorkoutCompletionDraft? authoritativeDraft;
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
      WorkoutCompletionDraft? authoritative;
      var conflict = false;
      await _firestore.runTransaction<void>((transaction) async {
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
        if (serverSnapshot.exists && serverSnapshot.data() != null) {
          final server = WorkoutCompletionDraft.fromMap(serverSnapshot.data()!);
          _verifyIdentity(server, draft.instanceId, draft.athleteId);
          if (server.revision > draft.revision) {
            authoritative = server;
            conflict = server.clientId != draft.clientId;
            return;
          }
          if (server.revision == draft.revision &&
              server.clientId != draft.clientId) {
            authoritative = server;
            conflict = true;
            return;
          }
          if (server.revision == draft.revision) {
            authoritative = server;
            return;
          }
        }
        transaction.set(draftRef, draft.toMap(includeServerTimestamp: true));
      });
      if (conflict) {
        if (authoritative != null) {
          await _localStore.write(authoritative!);
        }
        return WorkoutDraftSaveResult(
          WorkoutDraftSaveStatus.conflict,
          authoritativeDraft: authoritative,
        );
      }
      if (authoritative != null) {
        await _localStore.write(authoritative!);
      }
      return WorkoutDraftSaveResult(
        WorkoutDraftSaveStatus.saved,
        authoritativeDraft: authoritative,
      );
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
