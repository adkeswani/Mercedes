import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_list_screen.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/program_list_screen.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_list_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  final timestamp = DateTime.utc(2026);

  testWidgets('trainer libraries render seeded backend content',
      (tester) async {
    final exercise = ExerciseTemplate(
      id: 'release-canary-exercise',
      ownerId: 'release-canary-trainer',
      currentVersion: 1,
      version: ExerciseVersion(
        versionNumber: 1,
        name: 'Release Canary Exercise',
        description: 'Synthetic exercise',
        instructions: 'Controlled movement',
        exerciseType: ExerciseType.strength,
        measurementConfiguration: const ExerciseMeasurementConfiguration(
          primary: ExerciseMeasurementType.repetitions,
        ),
        publishedAt: timestamp,
        publishedBy: 'release-canary-trainer',
      ),
      createdAt: timestamp,
      createdBy: 'release-canary-trainer',
      updatedAt: timestamp,
      updatedBy: 'release-canary-trainer',
    );
    final workout = WorkoutTemplate(
      id: 'release-canary-workout',
      ownerId: 'release-canary-trainer',
      name: 'Release Canary Workout',
      workoutType: WorkoutType.fullBody,
      currentVersion: 1,
      createdAt: timestamp,
      createdBy: 'release-canary-trainer',
      updatedAt: timestamp,
      updatedBy: 'release-canary-trainer',
    );
    final program = Program(
      id: 'release-canary-program',
      name: 'Release Canary Program',
      ownerId: 'release-canary-trainer',
      type: ProgramType.assignable,
      status: ProgramStatus.published,
      currentVersion: 1,
      createdAt: timestamp,
      createdBy: 'release-canary-trainer',
      updatedAt: timestamp,
      updatedBy: 'release-canary-trainer',
    );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          exerciseTemplatesProvider.overrideWith(
            (ref) => Stream.value([exercise]),
          ),
        ],
        child: const MaterialApp(home: ExerciseListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Exercise'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          workoutTemplatesProvider.overrideWith(
            (ref) => Stream.value([workout]),
          ),
        ],
        child: const MaterialApp(home: WorkoutListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Workout'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          programsProvider.overrideWith((ref) => Stream.value([program])),
          programFoldersProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: const MaterialApp(home: ProgramListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Program'), findsOneWidget);
  });
}
