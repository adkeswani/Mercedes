import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_list_screen.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/programs/presentation/program_list_screen.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_list_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';

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
      tags: const ['Strength'],
      folderId: 'exercise-folder',
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
      tags: const ['Client', 'Power'],
      folderId: 'workout-folder',
      clientAthleteId: 'athlete-1',
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
      tags: const ['Client', 'Progression'],
      folderId: 'program-folder',
      clientAthleteId: 'athlete-1',
    );
    LibraryFolder folder(String id, String name, LibraryItemType itemType) =>
        LibraryFolder(
          id: id,
          ownerId: 'release-canary-trainer',
          name: name,
          itemType: itemType,
          createdAt: timestamp,
          createdBy: 'release-canary-trainer',
          updatedAt: timestamp,
          updatedBy: 'release-canary-trainer',
        );

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('release-canary-trainer')),
          ),
          exerciseTemplatesProvider.overrideWith(
            (ref) => Stream.value([exercise]),
          ),
          libraryFoldersProvider(LibraryItemType.exercise).overrideWith(
            (ref) => Stream.value([
              folder(
                'exercise-folder',
                'Exercise folder',
                LibraryItemType.exercise,
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: ExerciseListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Exercise'), findsOneWidget);
    expect(find.text('Exercise folder (1)'), findsOneWidget);
    expect(find.text('Strength'), findsWidgets);
    expect(find.text('Clients'), findsNothing);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('release-canary-trainer')),
          ),
          workoutTemplatesProvider.overrideWith(
            (ref) => Stream.value([workout]),
          ),
          libraryFoldersProvider(LibraryItemType.workout).overrideWith(
            (ref) => Stream.value([
              folder(
                'workout-folder',
                'Workout folder',
                LibraryItemType.workout,
              ),
            ]),
          ),
          activeTrainerClientNamesProvider.overrideWith(
            (ref) async => const {'athlete-1': 'Alex Athlete'},
          ),
        ],
        child: const MaterialApp(home: WorkoutListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Workout'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Alex Athlete (1)'), findsOneWidget);
    expect(find.text('Power'), findsWidgets);

    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('release-canary-trainer')),
          ),
          programsProvider.overrideWith((ref) => Stream.value([program])),
          programFoldersProvider.overrideWith(
            (ref) => Stream.value([
              folder(
                'program-folder',
                'Program folder',
                LibraryItemType.program,
              ),
            ]),
          ),
          activeTrainerClientNamesProvider.overrideWith(
            (ref) async => const {'athlete-1': 'Alex Athlete'},
          ),
        ],
        child: const MaterialApp(home: ProgramListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release Canary Program'), findsOneWidget);
    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Program folder (1)'), findsOneWidget);
    expect(find.text('Progression'), findsWidgets);
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}
