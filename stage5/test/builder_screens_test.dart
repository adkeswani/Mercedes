import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/presentation/program_builder_screen.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_builder_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);

  ExerciseTemplate exercise(String id, String name) => ExerciseTemplate(
        id: id,
        ownerId: 'trainer',
        currentVersion: 1,
        version: ExerciseVersion(
          versionNumber: 1,
          name: name,
          description: 'Description',
          instructions: 'Instructions',
          exerciseType: ExerciseType.strength,
          measurementConfiguration: const ExerciseMeasurementConfiguration(
            primary: ExerciseMeasurementType.repetitions,
          ),
          publishedAt: now,
          publishedBy: 'trainer',
        ),
        createdAt: now,
        createdBy: 'trainer',
        updatedAt: now,
        updatedBy: 'trainer',
      );

  WorkoutTemplate workout(String id, String name) => WorkoutTemplate(
        id: id,
        ownerId: 'trainer',
        name: name,
        workoutType: WorkoutType.fullBody,
        currentVersion: 2,
        createdAt: now,
        createdBy: 'trainer',
        updatedAt: now,
        updatedBy: 'trainer',
      );

  testWidgets('desktop workout builder supports drag and button commands',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('workoutTemplates').doc('draft').set({
      'name': 'Builder Workout',
      'workoutType': 'fullBody',
      'currentVersion': 0,
      'ownerId': 'trainer',
      'createdBy': 'trainer',
      'updatedBy': 'trainer',
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    });
    final repository = WorkoutTemplateRepository(firestore: firestore);
    final exercises = [exercise('ex-a', 'Squat'), exercise('ex-b', 'Row')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('trainer')),
          ),
          workoutTemplateRepositoryProvider.overrideWithValue(repository),
          exerciseTemplatesProvider.overrideWith(
            (ref) => Stream.value(exercises),
          ),
          libraryFoldersProvider(LibraryItemType.exercise).overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(
          home: WorkoutBuilderScreen(workoutId: 'draft'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Exercise Library'), findsOneWidget);
    expect(find.text('Workout canvas'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Add Squat to workout'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Add Squat to workout'));
    await tester.pumpAndSettle();
    expect(find.text('Squat'), findsNWidgets(2));

    final exerciseDrag = await tester.startGesture(
      tester.getCenter(find.text('Row').first),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await exerciseDrag.moveTo(
      tester.getCenter(find.bySemanticsLabel('Drop exercise at start').first),
      timeStamp: const Duration(milliseconds: 700),
    );
    await tester.pump();
    await exerciseDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Row'), findsNWidgets(2));
    expect(find.byTooltip('Move block down'), findsWidgets);
    expect(find.byTooltip('Duplicate block'), findsWidgets);
    expect(find.byTooltip('Remove block'), findsWidgets);
  });

  testWidgets('desktop program builder supports drag, phases, and controls',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final firestore = FakeFirebaseFirestore();
    await firestore.collection('programs').doc('program').set({
      'name': 'Builder Program',
      'description': 'Plan',
      'type': 'assignable',
      'status': 'draft',
      'currentVersion': 0,
      'ownerId': 'trainer',
      'createdBy': 'trainer',
      'updatedBy': 'trainer',
      'createdAt': now,
      'updatedAt': now,
      'deletedAt': null,
    });
    final repository = ProgramRepository(firestore: firestore);
    final workouts = [workout('workout-a', 'Strength Day')];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('trainer')),
          ),
          programRepositoryProvider.overrideWithValue(repository),
          workoutTemplatesProvider.overrideWith(
            (ref) => Stream.value(workouts),
          ),
          libraryFoldersProvider(LibraryItemType.workout).overrideWith(
            (ref) => Stream.value(const []),
          ),
          programFoldersProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          activeTrainerClientNamesProvider.overrideWith(
            (ref) async => const {},
          ),
        ],
        child: const MaterialApp(
          home: ProgramBuilderScreen(programId: 'program'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Workout Library'), findsOneWidget);
    expect(find.text('Chronological draft'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Add Strength Day to program'),
      findsOneWidget,
    );
    final workoutDrag = await tester.startGesture(
      tester.getCenter(find.text('Strength Day').first),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await workoutDrag.moveTo(
      tester.getCenter(find.bySemanticsLabel('Drop workout at start').first),
      timeStamp: const Duration(milliseconds: 700),
    );
    await tester.pump();
    await workoutDrag.up();
    await tester.pumpAndSettle();
    expect(find.text('Choose day'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Strength Day'), findsAtLeastNWidgets(2));
    expect(find.byTooltip('Move workout up'), findsOneWidget);
    expect(find.byTooltip('Duplicate workout entry'), findsOneWidget);

    await tester.tap(find.byTooltip('Add Strength Day to program'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Move workout up'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Move workout up').last);
    await tester.pump();

    await tester.tap(find.text('Add phase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Build');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Build'), findsOneWidget);
    expect(find.byTooltip('Move phase down'), findsOneWidget);
    expect(find.byTooltip('Remove phase'), findsOneWidget);
  });

  testWidgets('workout builder reloads when the edit route ID changes',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    for (final entry in const [
      ('first', 'First Workout'),
      ('second', 'Second Workout'),
    ]) {
      await firestore.collection('workoutTemplates').doc(entry.$1).set({
        'name': entry.$2,
        'workoutType': 'fullBody',
        'currentVersion': 0,
        'ownerId': 'trainer',
        'createdBy': 'trainer',
        'updatedBy': 'trainer',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });
    }
    final repository = WorkoutTemplateRepository(firestore: firestore);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('trainer')),
          ),
          workoutTemplateRepositoryProvider.overrideWithValue(repository),
          exerciseTemplatesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          libraryFoldersProvider(LibraryItemType.exercise).overrideWith(
            (ref) => Stream.value(const []),
          ),
        ],
        child: const MaterialApp(home: _WorkoutSwitchHarness()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'First Workout',
    );

    await tester.tap(find.text('Switch workout'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Second Workout',
    );
  });

  testWidgets('program builder reloads when the edit route ID changes',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    for (final entry in const [
      ('first', 'First Program'),
      ('second', 'Second Program'),
    ]) {
      await firestore.collection('programs').doc(entry.$1).set({
        'name': entry.$2,
        'description': entry.$2,
        'type': 'assignable',
        'status': 'draft',
        'currentVersion': 0,
        'ownerId': 'trainer',
        'createdBy': 'trainer',
        'updatedBy': 'trainer',
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      });
    }
    final repository = ProgramRepository(firestore: firestore);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('trainer')),
          ),
          programRepositoryProvider.overrideWithValue(repository),
          workoutTemplatesProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          libraryFoldersProvider(LibraryItemType.workout).overrideWith(
            (ref) => Stream.value(const []),
          ),
          programFoldersProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          activeTrainerClientNamesProvider.overrideWith(
            (ref) async => const {},
          ),
        ],
        child: const MaterialApp(home: _ProgramSwitchHarness()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'First Program',
    );

    await tester.tap(find.text('Switch program'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Second Program',
    );
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}

class _WorkoutSwitchHarness extends StatefulWidget {
  const _WorkoutSwitchHarness();

  @override
  State<_WorkoutSwitchHarness> createState() => _WorkoutSwitchHarnessState();
}

class _WorkoutSwitchHarnessState extends State<_WorkoutSwitchHarness> {
  var _id = 'first';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => _id = 'second'),
          child: const Text('Switch workout'),
        ),
        Expanded(child: WorkoutBuilderScreen(workoutId: _id)),
      ],
    );
  }
}

class _ProgramSwitchHarness extends StatefulWidget {
  const _ProgramSwitchHarness();

  @override
  State<_ProgramSwitchHarness> createState() => _ProgramSwitchHarnessState();
}

class _ProgramSwitchHarnessState extends State<_ProgramSwitchHarness> {
  var _id = 'first';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => setState(() => _id = 'second'),
          child: const Text('Switch program'),
        ),
        Expanded(child: ProgramBuilderScreen(programId: _id)),
      ],
    );
  }
}
