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
    );
    expect(restored.kind, WorkoutDraftRestoreKind.conflict);
    expect(restored.draft?.revision, 2);

    localStore.value = draft(revision: 3, clientId: 'client-local');
    restored = await repository.load(
      instanceId: 'instance-1',
      athleteId: 'athlete-1',
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
      draft(revision: 3, clientId: 'new-tab', rpe: 2),
    );
    expect(staleAsyncResult.status, WorkoutDraftSaveStatus.conflict);
    expect(staleAsyncResult.authoritativeDraft?.rpe, 8);
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
