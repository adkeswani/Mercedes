import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:stage5/features/workouts/data/workout_draft_local_store.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
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
    this.onDiagnostic,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _localStore = localStore ?? createWorkoutDraftLocalStore();

  final FirebaseFirestore _firestore;
  final WorkoutDraftLocalStore _localStore;

  @visibleForTesting
  final void Function(Map<String, Object?> event)? onDiagnostic;
  int _diagnosticOperation = 0;

  void _diagnose(
    int operation,
    String phase,
    String instanceId, {
    WorkoutCompletionDraft? draft,
    WorkoutCompletionDraft? server,
    String? currentClientId,
    int? transactionAttempt,
    WorkoutDraftSaveStatus? status,
  }) {
    onDiagnostic?.call({
      'operation': operation,
      'phase': phase,
      'workoutId': instanceId,
      if (draft != null) 'clientId': draft.clientId,
      if (draft != null) 'revision': draft.revision,
      if (server != null) 'serverClientId': server.clientId,
      if (server != null) 'serverRevision': server.revision,
      if (currentClientId != null) 'currentClientId': currentClientId,
      if (transactionAttempt != null) 'transactionAttempt': transactionAttempt,
      if (status != null) 'status': status.name,
    });
  }

  DocumentReference<Map<String, dynamic>> _instance(String instanceId) =>
      _firestore.collection('workoutInstances').doc(instanceId);

  DocumentReference<Map<String, dynamic>> _draft(String instanceId) =>
      _instance(instanceId).collection('completionDrafts').doc('current');

  Future<WorkoutCompletionDraft?> _readServerDraft(
    Transaction transaction,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    final ids = data['climbingSlotIds'];
    if (ids == null) return WorkoutCompletionDraft.fromMap(data);
    if (ids is! List ||
        ids.length > 9 ||
        ids.toSet().length != ids.length ||
        ids.any((id) => id is! String || id.isEmpty || id.contains('/'))) {
      throw const FormatException('Invalid climbing draft slot manifest');
    }
    final inputs = Map<String, dynamic>.from(data['slotInputs'] as Map);
    for (final id in ids.cast<String>()) {
      final child = await transaction.get(
        snapshot.reference.collection('climbingInputs').doc(id),
      );
      final input = child.data();
      if (!child.exists ||
          input == null ||
          input['revision'] != data['revision'] ||
          input['clientId'] != data['clientId'] ||
          inputs.containsKey(id)) {
        throw const FormatException('Incomplete climbing draft generation');
      }
      inputs[id] = Map<String, dynamic>.from(input)
        ..remove('slotOrder')
        ..remove('revision')
        ..remove('clientId')
        ..remove('serverUpdatedAt');
    }
    return WorkoutCompletionDraft.fromMap({...data, 'slotInputs': inputs});
  }

  Future<WorkoutDraftRestoreResult> load({
    required String instanceId,
    required String athleteId,
    required String currentClientId,
  }) async {
    final operation = ++_diagnosticOperation;
    _diagnose(operation, 'load-start', instanceId,
        currentClientId: currentClientId);
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
    _diagnose(operation, 'load-local-read', instanceId,
        draft: local, currentClientId: currentClientId);

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
      server = await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(_draft(instanceId));
        return _readServerDraft(transaction, snapshot);
      });
      if (server != null) {
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
    _diagnose(operation, 'load-server-read', instanceId,
        draft: local, server: server, currentClientId: currentClientId);

    final result = reconcileWorkoutDrafts(
      local: local,
      server: server,
      currentClientId: currentClientId,
    );
    final selected = result.draft;
    _diagnose(operation, 'load-selected', instanceId,
        draft: selected, server: server, currentClientId: currentClientId);
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
      _diagnose(operation, 'load-sync-local', instanceId,
          draft: local, server: server, currentClientId: currentClientId);
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
    final operation = ++_diagnosticOperation;
    _diagnose(operation, 'save-start', draft.instanceId, draft: draft);
    draft.validate();
    await _localStore.write(draft);
    _diagnose(operation, 'save-local-written', draft.instanceId, draft: draft);
    try {
      var transactionAttempt = 0;
      final result = await _firestore.runTransaction<WorkoutDraftSaveResult>((
        transaction,
      ) async {
        transactionAttempt++;
        _diagnose(operation, 'transaction-start', draft.instanceId,
            draft: draft, transactionAttempt: transactionAttempt);
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
        final server = await _readServerDraft(transaction, serverSnapshot);
        if (server != null) {
          _verifyIdentity(server, draft.instanceId, draft.athleteId);
        }
        final decision = decideWorkoutDraftSaveAttempt(
          draft: draft,
          server: server,
        );
        _diagnose(operation, 'transaction-decision', draft.instanceId,
            draft: draft,
            server: server,
            transactionAttempt: transactionAttempt,
            status: decision.result.status);
        if (!decision.shouldWrite) {
          return decision.result;
        }
        final climbing = {
          for (final entry in draft.slotInputs.entries)
            if (entry.value.containsKey('climbingType'))
              entry.key: climbingInputForStorage(entry.value),
        };
        final slotOrders = <String, int>{};
        if (climbing.isNotEmpty) {
          final instance = instanceSnapshot.data()!;
          final version = (await transaction.get(
            _firestore
                .collection('workoutTemplates')
                .doc(instance['workoutTemplateId'] as String)
                .collection('workoutTemplateVersions')
                .doc('${instance['workoutTemplateVersion']}'),
          ))
              .data();
          if (version == null ||
              version['storageFormat'] != 'typedWorkoutBlocksV1' ||
              version['publishState'] != 'published') {
            throw const FormatException(
                'Climbing draft needs a pinned workout');
          }
          final slots = version['slots'] as List;
          final blocks = version['blocks'] as List;
          for (final entry in climbing.entries) {
            final order = slots.indexWhere((s) => s['slotId'] == entry.key);
            if (order < 0) {
              throw const FormatException('Unknown climbing draft slot');
            }
            final block = blocks[slots[order]['blockSortOrder'] as int] as Map;
            if (block['type'] != entry.value['climbingType']) {
              throw const FormatException('Climbing draft type changed');
            }
            if (block['type'] == 'climbingCircuit') {
              validateClimbingRowManifest(
                entry.value['rowIds'],
                (block['rowIds'] as List).cast<String>(),
              );
            }
            slotOrders[entry.key] = order;
          }
        }
        final previousIds =
            serverSnapshot.data()?['climbingSlotIds'] as List? ?? const [];
        for (final id in previousIds.cast<String>()) {
          if (!climbing.containsKey(id)) {
            transaction.delete(draftRef.collection('climbingInputs').doc(id));
          }
        }
        for (final entry in climbing.entries) {
          transaction.set(
            draftRef.collection('climbingInputs').doc(entry.key),
            {
              ...entry.value,
              'slotOrder': slotOrders[entry.key],
              'revision': draft.revision,
              'clientId': draft.clientId,
              'serverUpdatedAt': FieldValue.serverTimestamp(),
            },
          );
        }
        final data = draft.toMap(includeServerTimestamp: true);
        if (climbing.isNotEmpty || previousIds.isNotEmpty) {
          data['climbingSlotIds'] = climbing.keys.toList();
          data['slotInputs'] = {
            for (final entry in draft.slotInputs.entries)
              if (!climbing.containsKey(entry.key)) entry.key: entry.value,
          };
        }
        transaction.set(draftRef, data);
        return decision.result;
      });
      final authoritative = result.authoritativeDraft;
      _diagnose(operation, 'save-result', draft.instanceId,
          draft: draft, server: authoritative, status: result.status);
      if (authoritative != null) {
        await _localStore.write(authoritative);
        _diagnose(
            operation, 'save-authoritative-local-written', draft.instanceId,
            draft: draft, server: authoritative, status: result.status);
      }
      _diagnose(operation, 'save-return', draft.instanceId,
          draft: draft, server: authoritative, status: result.status);
      return result;
    } on FirebaseException {
      _diagnose(operation, 'save-return', draft.instanceId,
          draft: draft, status: WorkoutDraftSaveStatus.offline);
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
