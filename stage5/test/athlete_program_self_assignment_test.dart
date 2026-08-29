import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/athlete_schedule_screen.dart';
import 'package:stage5/features/programs/presentation/enrollment_providers.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProgramRepository programRepository;
  late WorkoutInstanceRepository workoutInstanceRepository;
  late WorkoutTemplateRepository workoutRepository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    programRepository = ProgramRepository(firestore: firestore);
    workoutInstanceRepository = WorkoutInstanceRepository(firestore: firestore);
    workoutRepository = WorkoutTemplateRepository(firestore: firestore);
    final now = Timestamp.now();
    await firestore.collection('programs').doc('program-1').set({
      'name': 'Base Strength',
      'description': 'Build foundational strength.',
      'ownerId': 'coach-1',
      'type': 'assignable',
      'status': 'published',
      'currentVersion': 1,
      'createdBy': 'coach-1',
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    });
    await firestore
        .collection('programs')
        .doc('program-1')
        .collection('programVersions')
        .doc('1')
        .set({
      'versionNumber': 1,
      'publishedAt': now,
      'entries': [
        {
          'workoutTemplateId': 'workout-1',
          'workoutTemplateVersion': 2,
          'workoutName': 'Full Body A',
          'dayOffset': 0,
          'sortOrder': 0,
        },
        {
          'workoutTemplateId': 'workout-1',
          'workoutTemplateVersion': 2,
          'workoutName': 'Full Body A',
          'dayOffset': 2,
          'sortOrder': 1,
        },
      ],
    });
    await firestore.collection('workoutTemplates').doc('workout-1').set({
      'name': 'Full Body A',
      'workoutType': 'fullBody',
      'currentVersion': 2,
      'createdBy': 'coach-1',
      'createdAt': now,
      'updatedAt': now,
      'updatedBy': 'coach-1',
      'deletedAt': null,
    });
    await firestore.collection('workoutInstances').doc('upcoming').set({
      'programId': 'program-1',
      'programVersion': 1,
      'athleteId': 'athlete-1',
      'workoutTemplateId': 'workout-1',
      'workoutTemplateVersion': 2,
      'scheduledDate': '2099-01-01',
      'workoutType': 'fullBody',
      'assignedBy': 'coach-1',
      'assignedAt': now,
      'status': 'scheduled',
    });
    await firestore.collection('workoutInstances').doc('past').set({
      'programId': 'program-1',
      'programVersion': 1,
      'athleteId': 'athlete-1',
      'workoutTemplateId': 'workout-1',
      'workoutTemplateVersion': 2,
      'scheduledDate': '2000-01-01',
      'workoutType': 'fullBody',
      'assignedBy': 'coach-1',
      'assignedAt': now,
      'status': 'completed',
      'completedAt': now,
      'rpe': 7,
    });
  });

  test('program workout options contain each published workout once', () async {
    final container = ProviderContainer(
      overrides: [
        programRepositoryProvider.overrideWithValue(programRepository),
        workoutTemplateRepositoryProvider.overrideWithValue(workoutRepository),
      ],
    );
    addTearDown(container.dispose);

    final options = await container.read(
      programWorkoutOptionsProvider('program-1').future,
    );

    expect(options, hasLength(1));
    expect(options.single.template.name, 'Full Body A');
    expect(options.single.version, 2);
  });

  test(
      'self-service programs include owned personal programs without enrollment',
      () {
    final now = DateTime(2026, 1, 1);
    Program program(String id, String name, String type) => Program(
          id: id,
          ownerId: 'athlete-1',
          name: name,
          description: 'Description',
          type: type == 'personal'
              ? ProgramType.personal
              : ProgramType.assignable,
          status: ProgramStatus.published,
          currentVersion: 1,
          createdAt: now,
          createdBy: 'athlete-1',
          updatedAt: now,
          updatedBy: 'athlete-1',
        );

    final programs = athleteAccessiblePrograms(
      enrolledPrograms: [program('enrolled', 'Beta', 'assignable')],
      ownedPrograms: [
        program('personal', 'Alpha', 'personal'),
        program('owned-assignable', 'Excluded', 'assignable'),
      ],
    );

    expect(programs.map((item) => item.id), ['personal', 'enrolled']);
  });

  testWidgets('program card destination shows upcoming and past workouts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          programRepositoryProvider.overrideWithValue(programRepository),
          workoutInstanceRepositoryProvider
              .overrideWithValue(workoutInstanceRepository),
          workoutTemplateRepositoryProvider
              .overrideWithValue(workoutRepository),
        ],
        child: const MaterialApp(
          home: AthleteScheduleScreen(
            programId: 'program-1',
            athleteId: 'athlete-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Base Strength'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Past'), findsOneWidget);
    expect(find.text('Full Body A'), findsNWidgets(2));
    expect(find.textContaining('2099-01-01'), findsOneWidget);
    expect(find.textContaining('2000-01-01'), findsOneWidget);
  });
}
