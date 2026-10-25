import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/relationships/domain/trainer_client_relationship.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_workspace_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_workspace_screen.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/trainer_dashboard/presentation/trainer_dashboard_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

TrainerClientRelationship _relationship(String athleteId) {
  final now = DateTime.utc(2026, 1, 1);
  return TrainerClientRelationship(
    id: 'rel-$athleteId',
    trainerId: 'trainer-1',
    athleteId: athleteId,
    status: TrainerClientRelationshipStatus.active,
    startedAt: now,
    createdAt: now,
    createdBy: 'trainer-1',
    updatedAt: now,
    updatedBy: 'trainer-1',
  );
}

WorkoutInstance _workoutInstance({
  required String id,
  String? athleteProgramInstanceId,
}) {
  final now = DateTime(2026, 4, 1);
  return WorkoutInstance(
    id: id,
    programId: 'program-1',
    athleteId: 'athlete-1',
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

AthleteProgramInstance _programInstance() {
  final now = DateTime.utc(2026, 1, 1);
  return AthleteProgramInstance(
    id: 'program-instance-1',
    athleteOwnerId: 'athlete-1',
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

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required ProgramRepository programRepository,
  required WorkoutTemplateRepository workoutRepository,
  List<TrainerClientRelationship> relationships = const [],
  Map<String, String> names = const {},
  List<WorkoutInstance> schedule = const [],
  List<AthleteProgramInstance> programs = const [],
  List<TrainerActivityEvent> activity = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerClientsProvider.overrideWith(
          (ref) => Stream.value(relationships),
        ),
        activeTrainerClientNamesProvider.overrideWith(
          (ref) => Future.value(names),
        ),
        clientWorkspaceScheduleProvider.overrideWith(
          (ref) => Stream.value(schedule),
        ),
        managedAthleteProgramInstancesProvider.overrideWith(
          (ref) => Stream.value(programs),
        ),
        trainerDashboardProvider.overrideWith(
          (ref) => Future.value(
            TrainerDashboardPage(events: activity, isBounded: false),
          ),
        ),
        programRepositoryProvider.overrideWithValue(programRepository),
        workoutTemplateRepositoryProvider.overrideWithValue(
          workoutRepository,
        ),
      ],
      child: const MaterialApp(
        home: TrainerClientWorkspaceScreen(),
      ),
    ),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late ProgramRepository programRepository;
  late WorkoutTemplateRepository workoutRepository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    programRepository = ProgramRepository(firestore: firestore);
    workoutRepository = WorkoutTemplateRepository(firestore: firestore);
    final now = DateTime.utc(2026);
    await firestore.collection('programs').doc('program-1').set({
      'name': 'Foundation Strength',
      'ownerId': 'trainer-1',
      'type': 'assignable',
      'status': 'published',
      'currentVersion': 2,
      'createdAt': now,
      'createdBy': 'trainer-1',
      'updatedAt': now,
      'updatedBy': 'trainer-1',
      'deletedAt': null,
    });
    await firestore.collection('workoutTemplates').doc('template-1').set({
      'name': 'Pull Session',
      'ownerId': 'trainer-1',
      'workoutType': 'pull',
      'currentVersion': 1,
      'createdAt': now,
      'createdBy': 'trainer-1',
      'updatedAt': now,
      'updatedBy': 'trainer-1',
      'deletedAt': null,
    });
  });

  testWidgets('shows empty roster message when no clients', (tester) async {
    await _pumpWorkspace(
      tester,
      programRepository: programRepository,
      workoutRepository: workoutRepository,
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No athletes on your roster yet. Use "Manage roster" to '
        'add a client.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'defaults to the All tab and switches between Schedule, Programs, '
      'Workouts, and Activity', (tester) async {
    await _pumpWorkspace(
      tester,
      programRepository: programRepository,
      workoutRepository: workoutRepository,
      relationships: [_relationship('athlete-1')],
      names: {'athlete-1': 'Ada Athlete'},
      schedule: [
        _workoutInstance(id: 'independent-1'),
        _workoutInstance(
          id: 'program-linked-1',
          athleteProgramInstanceId: 'program-instance-1',
        ),
      ],
      programs: [_programInstance()],
      activity: [
        CommentActivityEvent(
          id: 'comment-1',
          occurredAt: DateTime(2026, 4, 1),
          athleteId: 'athlete-1',
          athleteName: 'Ada Athlete',
          workoutInstanceId: 'program-linked-1',
          comment: 'Great job',
          authorName: 'Coach',
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada Athlete'), findsWidgets);
    expect(
      find.text('Scheduled workouts (next 14d / last 7d)'),
      findsOneWidget,
    );
    expect(find.text('2'), findsOneWidget); // schedule count on the All tab

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('Pull Session'), findsNWidgets(2));

    await tester.tap(find.text('Programs'));
    await tester.pumpAndSettle();
    expect(find.text('Foundation Strength'), findsOneWidget);
    expect(find.textContaining('2026-01-01 to 2026-02-01'), findsOneWidget);

    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Pull Session'), findsOneWidget);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Coach commented'), findsOneWidget);
    expect(find.textContaining('Great job'), findsOneWidget);
  });
}
