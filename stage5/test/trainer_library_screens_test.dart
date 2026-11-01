import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_detail_screen.dart';
import 'package:stage5/features/exercises/presentation/exercise_form_screen.dart';
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
  testWidgets('trainer libraries render seeded backend content',
      (tester) async {
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

    final instructionRepository = _InstructionRepository(exercise);
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
          exerciseTemplateRepositoryProvider
              .overrideWithValue(instructionRepository),
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
    expect(find.text('Instruction Library'), findsOneWidget);
    expect(find.byTooltip('New instructions'), findsOneWidget);
    expect(find.text('Release Canary Exercise'), findsOneWidget);
    expect(find.text('Exercise folder (1)'), findsOneWidget);
    expect(find.text('Strength'), findsWidgets);
    expect(find.text('Clients'), findsNothing);
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete instructions?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    instructionRepository.referenced = true;
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
        find.text(
          'Cannot delete — these instructions are used in a workout',
        ),
        findsOneWidget);
    expect(find.text(exercise.name), findsOneWidget);

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

  testWidgets('empty Instruction library uses instruction terminology',
      (tester) async {
    await tester.pumpWidget(_instructionHarness(
      child: const ExerciseListScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Instruction Library'), findsOneWidget);
    expect(find.text('No instructions yet. Tap + to create an entry.'),
        findsOneWidget);
    expect(find.byTooltip('New instructions'), findsOneWidget);
  });

  testWidgets('instruction authoring labels retain existing entry content',
      (tester) async {
    await tester.pumpWidget(_instructionHarness(
      child: const ExerciseFormScreen(),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'New instructions'), findsOneWidget);
    await tester.pumpWidget(_instructionHarness(
      child: ExerciseFormScreen(exerciseId: exercise.id),
      exercises: [exercise],
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Edit instructions'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Instructions'),
            )
            .controller!
            .text,
        exercise.instructions);
  });

  testWidgets('Instruction library errors use instruction terminology',
      (tester) async {
    await tester.pumpWidget(_instructionHarness(
      child: const ExerciseListScreen(),
      loadError: StateError('test load failure'),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load instructions:'), findsOneWidget);
  });

  testWidgets(
      'instruction detail keeps exercise identity and edit authorization',
      (tester) async {
    await tester.pumpWidget(_instructionHarness(
      child: ExerciseDetailScreen(exerciseId: exercise.id),
      repository: _InstructionRepository(exercise),
    ));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Instructions'), findsOneWidget);
    expect(find.text(exercise.name), findsOneWidget);
    expect(find.text(exercise.instructions), findsOneWidget);
    expect(find.byTooltip('Edit instructions'), findsOneWidget);
    await tester.pumpWidget(_instructionHarness(
      child: ExerciseDetailScreen(exerciseId: exercise.id),
      repository: _InstructionRepository(exercise),
      userId: 'another-athlete',
    ));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit instructions'), findsNothing);
    await tester.pumpWidget(_instructionHarness(
      child: const ExerciseDetailScreen(exerciseId: 'missing'),
      repository: _InstructionRepository(exercise),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Instructions not found'), findsOneWidget);
  });
}

Widget _instructionHarness({
  required Widget child,
  List<ExerciseTemplate> exercises = const [],
  ExerciseTemplateRepository? repository,
  Object? loadError,
  String userId = 'release-canary-trainer',
}) =>
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        authStateProvider
            .overrideWith((ref) => Stream.value(_FakeUser(userId))),
        exerciseTemplatesProvider.overrideWith(
          (ref) => loadError == null
              ? Stream.value(exercises)
              : Stream.error(loadError),
        ),
        libraryFoldersProvider(LibraryItemType.exercise).overrideWith(
          (ref) => Stream.value([]),
        ),
        if (repository != null)
          exerciseTemplateRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(home: child),
    );

class _InstructionRepository extends Fake
    implements ExerciseTemplateRepository {
  _InstructionRepository(this.exercise);
  final ExerciseTemplate exercise;
  bool referenced = false;

  @override
  Future<ExerciseTemplate?> getById(String id, {int? versionNumber}) async =>
      id == exercise.id ? exercise : null;

  @override
  Future<bool> isExerciseReferenced(String exerciseId) async => referenced;
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}
