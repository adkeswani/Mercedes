import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/relationships/domain/trainer_client_workspace.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';

AthleteProgramInstance _programInstance({
  required String id,
  required String athleteOwnerId,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return AthleteProgramInstance(
    id: id,
    athleteOwnerId: athleteOwnerId,
    assigningTrainerId: 'trainer-1',
    sourceProgramId: 'program-1',
    sourceProgramVersion: 1,
    relationshipMode: ProgramRelationshipMode.subscribed,
    startDate: '2026-01-01',
    expectedEndDate: '2026-02-01',
    workoutCount: 4,
    status: AthleteProgramInstanceStatus.active,
    linkedAt: now,
    createdAt: now,
    createdBy: 'trainer-1',
    updatedAt: now,
    updatedBy: 'trainer-1',
  );
}

WorkoutInstance _workoutInstance({
  required String id,
  required String athleteId,
  String? athleteProgramInstanceId,
}) {
  final now = DateTime(2026, 4, 1);
  return WorkoutInstance(
    id: id,
    programId: 'program-1',
    athleteId: athleteId,
    workoutTemplateId: 'template-1',
    workoutTemplateVersion: 1,
    scheduledDate: '2026-04-15',
    assignedBy: 'trainer-1',
    assignedAt: now,
    status: WorkoutInstanceStatus.scheduled,
    workoutType: WorkoutType.pull,
    createdAt: now,
    updatedAt: now,
    athleteProgramInstanceId: athleteProgramInstanceId,
  );
}

TrainerActivityEvent _activityEvent({
  required String id,
  required String athleteId,
}) {
  return CommentActivityEvent(
    id: id,
    occurredAt: DateTime(2026, 4, 1),
    athleteId: athleteId,
    athleteName: 'Athlete $athleteId',
    workoutInstanceId: 'instance-1',
    comment: 'Nice work',
    authorName: 'Coach',
  );
}

void main() {
  group('clientWorkspaceTabLabel', () {
    test('labels every tab', () {
      expect(clientWorkspaceTabLabel(ClientWorkspaceTab.all), 'All');
      expect(clientWorkspaceTabLabel(ClientWorkspaceTab.schedule), 'Schedule');
      expect(clientWorkspaceTabLabel(ClientWorkspaceTab.programs), 'Programs');
      expect(clientWorkspaceTabLabel(ClientWorkspaceTab.workouts), 'Workouts');
      expect(clientWorkspaceTabLabel(ClientWorkspaceTab.activity), 'Activity');
    });
  });

  group('filterProgramInstancesForAthlete', () {
    test('keeps only instances owned by the given athlete', () {
      final mine = _programInstance(id: 'a', athleteOwnerId: 'athlete-1');
      final other = _programInstance(id: 'b', athleteOwnerId: 'athlete-2');

      final result =
          filterProgramInstancesForAthlete([mine, other], 'athlete-1');

      expect(result, [mine]);
    });
  });

  group('filterActivityEventsForAthlete', () {
    test('keeps only events for the given athlete', () {
      final mine = _activityEvent(id: 'e1', athleteId: 'athlete-1');
      final other = _activityEvent(id: 'e2', athleteId: 'athlete-2');

      final result = filterActivityEventsForAthlete([mine, other], 'athlete-1');

      expect(result, [mine]);
    });
  });

  group('filterIndependentWorkouts', () {
    test('keeps only instances without a program instance link', () {
      final independent = _workoutInstance(id: 'w1', athleteId: 'athlete-1');
      final programLinked = _workoutInstance(
        id: 'w2',
        athleteId: 'athlete-1',
        athleteProgramInstanceId: 'instance-1',
      );

      final result =
          filterIndependentWorkouts([independent, programLinked]);

      expect(result, [independent]);
    });
  });
}
