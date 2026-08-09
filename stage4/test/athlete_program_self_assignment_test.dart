import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage4/features/programs/data/program_repository.dart';
import 'package:stage4/features/programs/presentation/athlete_schedule_screen.dart';
import 'package:stage4/features/programs/presentation/program_providers.dart';
import 'package:stage4/features/workouts/data/workout_template_repository.dart';
import 'package:stage4/features/workouts/presentation/workout_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProgramRepository programRepository;
  late WorkoutTemplateRepository workoutRepository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    programRepository = ProgramRepository(firestore: firestore);
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

  testWidgets('program card destination shows a read-only published schedule',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          programRepositoryProvider.overrideWithValue(programRepository),
        ],
        child: const MaterialApp(
          home: AthleteProgramOverviewScreen(programId: 'program-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Base Strength'), findsOneWidget);
    expect(find.text('Build foundational strength.'), findsOneWidget);
    expect(find.text('Published schedule'), findsOneWidget);
    expect(find.text('Full Body A'), findsNWidgets(2));
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 3'), findsOneWidget);
  });
}
