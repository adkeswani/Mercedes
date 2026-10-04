import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';

void main() {
  WorkoutCompletionDraft draft({
    int revision = 1,
    String athleteId = 'athlete-1',
    String instanceId = 'instance-1',
    String clientId = 'client-a',
    DateTime? updatedAt,
    DateTime? serverUpdatedAt,
  }) {
    return WorkoutCompletionDraft(
      instanceId: instanceId,
      athleteId: athleteId,
      rpe: 7,
      durationMinutes: 55,
      athleteNotes: 'Felt strong',
      currentStep: 2,
      slotInputs: const {
        'slot-1': {'notes': 'Controlled tempo'},
      },
      revision: revision,
      clientId: clientId,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 4, 12),
      serverUpdatedAt: serverUpdatedAt,
      sourceRoute: '/athlete/workouts/$instanceId',
    );
  }

  test('round trips the versioned draft schema', () {
    final original = draft();
    final restored = WorkoutCompletionDraft.fromMap(original.toMap());

    expect(restored.instanceId, original.instanceId);
    expect(restored.athleteId, original.athleteId);
    expect(restored.rpe, 7);
    expect(restored.durationMinutes, 55);
    expect(restored.athleteNotes, 'Felt strong');
    expect(restored.currentStep, 2);
    expect(restored.slotInputs['slot-1']?['notes'], 'Controlled tempo');
    expect(restored.revision, 1);
  });

  test('reads Firestore timestamps and rejects unsupported schemas', () {
    final map = draft().toMap()
      ..['serverUpdatedAt'] = Timestamp.fromDate(DateTime.utc(2026, 10, 4));
    expect(WorkoutCompletionDraft.fromMap(map).serverUpdatedAt, isNotNull);

    map['schemaVersion'] = 99;
    expect(
      () => WorkoutCompletionDraft.fromMap(map),
      throwsFormatException,
    );
  });

  test('rejects invalid identity, values, and source route', () {
    for (final invalid in [
      {...draft().toMap(), 'athleteId': ''},
      {...draft().toMap(), 'rpe': 11},
      {...draft().toMap(), 'revision': 0},
      {...draft().toMap(), 'sourceRoute': '/'},
    ]) {
      expect(
        () => WorkoutCompletionDraft.fromMap(invalid),
        throwsFormatException,
      );
    }
  });

  test('restores local-only progress for offline startup', () {
    final result = reconcileWorkoutDrafts(
      local: draft(),
      server: null,
      currentClientId: 'client-a',
    );

    expect(result.kind, WorkoutDraftRestoreKind.local);
    expect(result.draft?.revision, 1);
    expect(result.message, contains('device'));
  });

  test('chooses server when its revision is newer', () {
    final result = reconcileWorkoutDrafts(
      local: draft(revision: 3),
      server: draft(revision: 4, clientId: 'client-b'),
      currentClientId: 'client-a',
    );

    expect(result.kind, WorkoutDraftRestoreKind.conflict);
    expect(result.draft?.revision, 4);
  });

  test('chooses local when its revision is newer', () {
    final result = reconcileWorkoutDrafts(
      local: draft(revision: 5),
      server: draft(revision: 4, clientId: 'client-b'),
      currentClientId: 'client-a',
    );

    expect(result.kind, WorkoutDraftRestoreKind.conflict);
    expect(result.draft?.revision, 5);
  });

  test('breaks equal-revision tab conflicts by server time then client ID', () {
    final local = draft(
      revision: 2,
      clientId: 'client-z',
      serverUpdatedAt: DateTime.utc(2026, 10, 4, 12),
    );
    final server = draft(
      revision: 2,
      clientId: 'client-a',
      serverUpdatedAt: DateTime.utc(2026, 10, 4, 13),
    );

    expect(compareWorkoutDrafts(local, server), lessThan(0));
    expect(
      reconcileWorkoutDrafts(
        local: local,
        server: server,
        currentClientId: 'client-z',
      ).draft?.clientId,
      'client-a',
    );
  });

  test('newer server revision from the current tab is not a conflict', () {
    final result = reconcileWorkoutDrafts(
      local: draft(revision: 3, clientId: 'client-a'),
      server: draft(revision: 4, clientId: 'client-a'),
      currentClientId: 'client-a',
    );

    expect(result.kind, WorkoutDraftRestoreKind.server);
    expect(result.draft?.revision, 4);
    expect(result.message, isNot(contains('another')));
  });
}
