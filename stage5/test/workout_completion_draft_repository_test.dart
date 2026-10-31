import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late _FakeLocalStore localStore;
  late WorkoutCompletionDraftRepository repository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    localStore = _FakeLocalStore();
    repository = WorkoutCompletionDraftRepository(
      firestore: firestore,
      localStore: localStore,
    );
    await firestore.collection('workoutInstances').doc('instance-1').set({
      'athleteId': 'athlete-1',
      'status': 'scheduled',
    });
  });

  WorkoutCompletionDraft draft({
    int revision = 1,
    String athleteId = 'athlete-1',
    String instanceId = 'instance-1',
    String clientId = 'client-a',
    int rpe = 6,
  }) {
    return WorkoutCompletionDraft(
      instanceId: instanceId,
      athleteId: athleteId,
      rpe: rpe,
      durationMinutes: 45,
      revision: revision,
      clientId: clientId,
      updatedAt: DateTime.utc(2026, 10, 4, 12, revision),
      sourceRoute: '/athlete/workouts/$instanceId',
    );
  }

  Future<WorkoutCompletionDraft> climbingDraft({
    int revision = 1,
    String clientId = 'client-a',
  }) async {
    final ids = [for (var i = 0; i < 9; i++) 'row-$i'];
    final slotIds = [for (var i = 0; i < 9; i++) 'slot-$i'];
    await firestore.collection('workoutInstances').doc('instance-1').update({
      'workoutTemplateId': 'workout',
      'workoutTemplateVersion': 1,
    });
    await firestore
        .collection('workoutTemplates')
        .doc('workout')
        .collection('workoutTemplateVersions')
        .doc('1')
        .set({
      'storageFormat': 'typedWorkoutBlocksV1',
      'publishState': 'published',
      'slotIds': slotIds,
      'slots': [
        for (var i = 0; i < 9; i++) {'slotId': slotIds[i], 'blockSortOrder': i},
      ],
      'blocks': [
        for (var i = 0; i < 9; i++) {'type': 'climbingCircuit', 'rowIds': ids},
      ],
    });
    return draft(revision: revision, clientId: clientId).copyWith(slotInputs: {
      for (final slotId in slotIds)
        slotId: {
          'climbingType': 'climbingCircuit',
          'notes': 'Circuit note',
          'rpe': null,
          'circuitRows': [
            for (final id in ids)
              {
                'rowId': id,
                'completed': true,
                'notes': 'Controlled',
                'rpe': 7,
              },
          ],
        },
    });
  }

  test('rejects climbing recovery against an unpublished pinned version',
      () async {
    final value = await climbingDraft(revision: 2);
    await firestore
        .collection('workoutTemplates')
        .doc('workout')
        .collection('workoutTemplateVersions')
        .doc('1')
        .update({'publishState': 'draft'});
    await expectLater(repository.save(value), throwsFormatException);
    expect(
        (await firestore
                .collection('workoutInstances')
                .doc('instance-1')
                .collection('completionDrafts')
                .doc('current')
                .get())
            .exists,
        isFalse);
  });

  test('atomically stores and restores nine slots with nine climbing rows each',
      () async {
    final value = await climbingDraft(revision: 2);
    expect((await repository.save(value)).status, WorkoutDraftSaveStatus.saved);
    final ref = firestore
        .collection('workoutInstances')
        .doc('instance-1')
        .collection('completionDrafts')
        .doc('current');
    final primary = (await ref.get()).data()!;
    expect(primary['climbingSlotIds'], value.slotInputs.keys.toList());
    expect(primary['slotInputs'], isEmpty);
    expect((await ref.collection('climbingInputs').get()).docs.length, 9);
    localStore.value = null;
    final restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );
    expect(restored.kind, WorkoutDraftRestoreKind.server);
    expect(restored.draft!.slotInputs.length, 9);
    expect(restored.draft!.slotInputs['slot-8']!['circuitRows'],
        value.slotInputs['slot-8']!['circuitRows']);
  });

  test('sharded conflict retains authoritative climbing inputs', () async {
    final current = await climbingDraft(revision: 4, clientId: 'other-tab');
    await repository.save(current);
    final stale = current.copyWith(rpe: 2);
    final incoming = WorkoutCompletionDraft(
      instanceId: stale.instanceId,
      athleteId: stale.athleteId,
      rpe: stale.rpe,
      durationMinutes: stale.durationMinutes,
      revision: 4,
      clientId: 'current-tab',
      updatedAt: stale.updatedAt,
      sourceRoute: stale.sourceRoute,
      slotInputs: stale.slotInputs,
    );
    final result = await repository.save(incoming);
    expect(result.status, WorkoutDraftSaveStatus.conflict);
    expect(result.authoritativeDraft!.clientId, 'other-tab');
    expect(result.authoritativeDraft!.rpe, current.rpe);
    expect(result.authoritativeDraft!.slotInputs['slot-8']!['circuitRows'],
        current.slotInputs['slot-8']!['circuitRows']);
  });

  test('rejects missing or mismatched climbing draft generations', () async {
    await repository.save(await climbingDraft(revision: 2));
    final child = firestore
        .collection('workoutInstances')
        .doc('instance-1')
        .collection('completionDrafts')
        .doc('current')
        .collection('climbingInputs')
        .doc('slot-8');
    localStore.value = null;
    await child.update({'revision': 1});
    await expectLater(
      repository.load(
        instanceId: 'instance-1',
        athleteId: 'athlete-1',
        currentClientId: 'client-a',
      ),
      throwsFormatException,
    );
    await child.delete();
    await expectLater(
      repository.load(
        instanceId: 'instance-1',
        athleteId: 'athlete-1',
        currentClientId: 'client-a',
      ),
      throwsFormatException,
    );
  });

  test('saves locally and on the server', () async {
    final result = await repository.save(draft());

    expect(result.status, WorkoutDraftSaveStatus.saved);
    expect(localStore.value?.revision, 1);
    final server = await firestore
        .collection('workoutInstances')
        .doc('instance-1')
        .collection('completionDrafts')
        .doc('current')
        .get();
    expect(server.data()?['revision'], 1);
  });

  test('restores server-newer and local-newer conflicts deterministically',
      () async {
    await repository.save(draft(revision: 2));
    localStore.value = draft(revision: 1, clientId: 'client-local');
    var restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );
    expect(restored.kind, WorkoutDraftRestoreKind.conflict);
    expect(restored.draft?.revision, 2);

    localStore.value = draft(revision: 3, clientId: 'client-local');
    restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );
    expect(restored.kind, WorkoutDraftRestoreKind.local);
    expect(restored.draft?.revision, 3);
    final synchronized = await firestore
        .collection('workoutInstances')
        .doc('instance-1')
        .collection('completionDrafts')
        .doc('current')
        .get();
    expect(synchronized.data()?['revision'], 3);
  });

  test('caches a server-only draft locally for later offline restore',
      () async {
    await repository.save(draft(revision: 2));
    localStore.value = null;

    final restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );

    expect(restored.kind, WorkoutDraftRestoreKind.server);
    expect(localStore.value?.revision, 2);
  });

  test('rejects a stale write from a second tab', () async {
    await repository.save(draft(revision: 4, clientId: 'new-tab', rpe: 8));

    final result = await repository.save(
      draft(revision: 4, clientId: 'old-tab', rpe: 3),
    );

    expect(result.status, WorkoutDraftSaveStatus.conflict);
    expect(result.authoritativeDraft?.clientId, 'new-tab');
    expect(result.authoritativeDraft?.rpe, 8);

    final staleAsyncResult = await repository.save(
      draft(revision: 3, clientId: 'old-tab', rpe: 2),
    );
    expect(staleAsyncResult.status, WorkoutDraftSaveStatus.conflict);
    expect(staleAsyncResult.authoritativeDraft?.rpe, 8);
  });

  test('same-tab recreation restores without a false conflict', () async {
    const stableClientId = 'stable-tab-client';
    await repository.save(
      draft(revision: 4, clientId: stableClientId, rpe: 8),
    );
    final recreatedRepository = WorkoutCompletionDraftRepository(
      firestore: firestore,
      localStore: localStore,
    );

    final restored = await recreatedRepository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: stableClientId,
    );

    expect(restored.kind, WorkoutDraftRestoreKind.server);
    expect(restored.draft?.clientId, stableClientId);
    expect(restored.message, isNot(contains('another')));
  });

  test('same-client lifecycle save racing recreation is idempotent', () async {
    const stableClientId = 'stable-tab-client';
    await repository.save(
      draft(revision: 4, clientId: stableClientId, rpe: 8),
    );
    final recreatedRepository = WorkoutCompletionDraftRepository(
      firestore: firestore,
      localStore: localStore,
    );

    final duplicate = await recreatedRepository.save(
      draft(revision: 4, clientId: stableClientId, rpe: 3),
    );

    expect(duplicate.status, WorkoutDraftSaveStatus.saved);
    expect(localStore.value?.clientId, stableClientId);
    expect(localStore.value?.rpe, 8);
  });

  test('adopts a newer same-client server revision without conflict', () async {
    await repository.save(draft(revision: 3, clientId: 'client-a', rpe: 8));
    localStore.value = draft(revision: 2, clientId: 'client-a', rpe: 6);

    final restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );

    expect(restored.kind, WorkoutDraftRestoreKind.server);
    expect(restored.draft?.revision, 3);
    expect(restored.draft?.rpe, 8);
    expect(restored.message, isNot(contains('another')));
    expect(localStore.value?.revision, 3);
  });

  test('reports a newer different-client server revision as conflict',
      () async {
    await repository.save(draft(revision: 3, clientId: 'other-tab', rpe: 8));
    localStore.value = draft(revision: 2, clientId: 'current-tab', rpe: 6);

    final restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'current-tab',
    );

    expect(restored.kind, WorkoutDraftRestoreKind.conflict);
    expect(restored.draft?.clientId, 'other-tab');
    expect(restored.draft?.revision, 3);
  });

  test('syncs a newer same-client local revision as pending progress',
      () async {
    await repository.save(draft(revision: 2, clientId: 'client-a', rpe: 6));
    localStore.value = draft(revision: 3, clientId: 'client-a', rpe: 8);

    final restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );

    expect(restored.kind, WorkoutDraftRestoreKind.local);
    expect(restored.draft?.revision, 3);
    expect(restored.draft?.rpe, 8);
    final server = await firestore
        .collection('workoutInstances')
        .doc('instance-1')
        .collection('completionDrafts')
        .doc('current')
        .get();
    expect(server.data()?['revision'], 3);
  });

  test('stale same-client save adopts a late lifecycle revision', () async {
    await repository.save(draft(revision: 4, clientId: 'client-a', rpe: 8));

    final result = await repository.save(
      draft(revision: 3, clientId: 'client-a', rpe: 6),
    );

    expect(result.status, WorkoutDraftSaveStatus.saved);
    expect(result.authoritativeDraft?.revision, 4);
    expect(result.authoritativeDraft?.rpe, 8);
    expect(localStore.value?.revision, 4);
  });

  test('transaction retries do not retain a superseded conflict decision', () {
    final pending = draft(revision: 4, clientId: 'current-tab', rpe: 8);
    final supersededAttempt = decideWorkoutDraftSaveAttempt(
      draft: pending,
      server: draft(revision: 4, clientId: 'other-tab', rpe: 6),
    );
    final finalAttempt = decideWorkoutDraftSaveAttempt(
      draft: pending,
      server: draft(revision: 4, clientId: 'current-tab', rpe: 8),
    );

    expect(
      supersededAttempt.result.status,
      WorkoutDraftSaveStatus.conflict,
    );
    expect(finalAttempt.result.status, WorkoutDraftSaveStatus.saved);
    expect(finalAttempt.result.authoritativeDraft?.clientId, 'current-tab');
  });

  test('rejects ownership mismatch and completed instances', () async {
    expect(
      () => repository.save(draft(athleteId: 'other-athlete')),
      throwsStateError,
    );
    await firestore.collection('workoutInstances').doc('instance-1').update({
      'status': 'completed',
    });
    expect(() => repository.save(draft()), throwsStateError);
  });

  test('removes invalid local identity and reports a safe warning', () async {
    localStore.value = draft(athleteId: 'other-athlete');

    final result = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
      currentClientId: 'client-a',
    );

    expect(result.kind, WorkoutDraftRestoreKind.invalidLocal);
    expect(localStore.value, isNull);
    expect(result.message, contains('invalid'));
  });

  test('clearLocal verifies ownership before deleting', () async {
    localStore.value = draft(athleteId: 'other-athlete');
    expect(
      () => repository.clearLocal(
        instanceId: 'instance-1',
        athleteId: 'athlete-1',
      ),
      throwsStateError,
    );

    localStore.value = draft();
    await repository.clearLocal(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
    );
    expect(localStore.value, isNull);
  });

  test('completion cleanup verifies the completed parent before deleting',
      () async {
    localStore.value = draft(athleteId: 'stale-athlete');
    await firestore.collection('workoutInstances').doc('instance-1').update({
      'status': 'completed',
    });

    await repository.clearLocalAfterCompletion(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
    );

    expect(localStore.value, isNull);
    expect(
      () => repository.clearLocalAfterCompletion(
        instanceId: 'instance-1',
        athleteId: 'other-athlete',
      ),
      throwsStateError,
    );
  });
}

class _FakeLocalStore implements WorkoutDraftLocalStore {
  WorkoutCompletionDraft? value;

  @override
  Future<void> delete(String instanceId) async {
    value = null;
  }

  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async => value;

  @override
  Future<void> write(WorkoutCompletionDraft draft) async {
    value = draft;
  }
}
