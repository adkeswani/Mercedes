import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_builder_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  testWidgets('Add menu lists all block types', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Standard Exercise'), findsOneWidget);
    expect(find.text('Timed Interval'), findsOneWidget);
    expect(find.text('Circuit'), findsOneWidget);
    expect(find.text('Climbing Route'), findsOneWidget);
    expect(find.text('AMRAP'), findsOneWidget);
  });

  testWidgets('creates a timed interval block with exercises', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timed Interval'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bike'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bike'), findsOneWidget);
    expect(find.textContaining('8 rounds'), findsOneWidget);
    expect(find.textContaining('30s work'), findsOneWidget);
    expect(find.textContaining('15s rest'), findsOneWidget);
  });

  testWidgets('creates a circuit block with sets/reps per exercise',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Circuit'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push-up'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Sets'), '3');
    await tester.enterText(find.widgetWithText(TextField, 'Reps'), '12');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Push-up'), findsOneWidget);
    expect(find.textContaining('3 rounds'), findsOneWidget);
    expect(find.textContaining('1 exercises'), findsOneWidget);
  });

  testWidgets('creates an AMRAP block with a time cap', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('AMRAP'));
    await tester.tap(find.text('AMRAP'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burpee'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Burpee'), findsOneWidget);
    expect(find.textContaining('AMRAP · 600s time cap'), findsOneWidget);
  });

  testWidgets('creates a climbing route block', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Climbing Route'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overhang Route'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Grade (e.g. V4)'), 'V4');
    await tester.enterText(find.widgetWithText(TextField, 'Color'), 'Red');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Overhang Route'), findsOneWidget);
    expect(find.textContaining('V4 · Red'), findsOneWidget);
  });

  testWidgets('edits an existing circuit block via the edit icon',
      (tester) async {
    final repository = _VersionedWorkoutRepository();
    final workout = _workout(id: 'editable', currentVersion: 1);
    repository.versions['editable'] = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.utc(2026),
      blocks: [
        CircuitBlock(
          blockId: 'block-1',
          sortOrder: 0,
          rounds: 3,
          restBetweenRoundsSeconds: 60,
          slots: [
            ExerciseSlot(
              slotId: 'slot-1',
              exerciseId: 'ex-pushup',
              exerciseName: 'Push-up',
              sortOrder: 0,
              mode: ExerciseMode.reps,
              sets: 3,
              reps: '10',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _harness(repository: repository, workout: workout),
    );
    await tester.pumpAndSettle();

    expect(find.text('Push-up'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit prescription'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Rounds'), '5');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 rounds'), findsOneWidget);
  });
}

Widget _harness({
  _VersionedWorkoutRepository? repository,
  WorkoutTemplate? workout,
}) {
  final repo = repository ?? _VersionedWorkoutRepository();
  final template = workout ?? _workout(id: 'draft', currentVersion: 0);
  final exercises = [
    _exercise(id: 'ex-bike', name: 'Bike'),
    _exercise(id: 'ex-pushup', name: 'Push-up'),
    _exercise(id: 'ex-burpee', name: 'Burpee'),
    _exercise(id: 'ex-route', name: 'Overhang Route'),
  ];

  final router = GoRouter(
    initialLocation: '/workouts/${template.id}',
    routes: [
      GoRoute(
        path: '/workouts',
        builder: (_, __) =>
            const Scaffold(body: Text('Workout library destination')),
      ),
      GoRoute(
        path: '/workouts/:id',
        builder: (_, state) => WorkoutBuilderScreen(
          workoutId: state.pathParameters['id'],
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream.value(_FakeUser('trainer-1')),
      ),
      workoutTemplateRepositoryProvider.overrideWithValue(repo),
      workoutTemplatesProvider.overrideWith((ref) => Stream.value([template])),
      exerciseTemplatesProvider.overrideWith((ref) => Stream.value(exercises)),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

WorkoutTemplate _workout({required String id, required int currentVersion}) {
  final timestamp = DateTime.utc(2026);
  return WorkoutTemplate(
    id: id,
    ownerId: 'trainer-1',
    name: 'Builder Workout',
    workoutType: WorkoutType.fullBody,
    currentVersion: currentVersion,
    createdAt: timestamp,
    createdBy: 'trainer-1',
    updatedAt: timestamp,
    updatedBy: 'trainer-1',
  );
}

ExerciseTemplate _exercise({required String id, required String name}) {
  final timestamp = DateTime.utc(2026);
  return ExerciseTemplate(
    id: id,
    ownerId: 'trainer-1',
    currentVersion: 1,
    version: ExerciseVersion(
      versionNumber: 1,
      name: name,
      description: 'Description for $name',
      instructions: 'Instructions for $name',
      exerciseType: ExerciseType.strength,
      measurementConfiguration: const ExerciseMeasurementConfiguration(
        primary: ExerciseMeasurementType.repetitions,
      ),
      publishedAt: timestamp,
      publishedBy: 'trainer-1',
    ),
    createdAt: timestamp,
    createdBy: 'trainer-1',
    updatedAt: timestamp,
    updatedBy: 'trainer-1',
  );
}

class _VersionedWorkoutRepository extends WorkoutTemplateRepository {
  _VersionedWorkoutRepository() : super(firestore: FakeFirebaseFirestore());

  final Map<String, WorkoutTemplateVersion> versions = {};
  int _idCounter = 0;

  @override
  Future<WorkoutTemplate?> getById(String id) async =>
      _workout(id: id, currentVersion: versions.containsKey(id) ? 1 : 0);

  @override
  Future<WorkoutTemplateVersion?> getVersion(
    String workoutTemplateId,
    int versionNumber,
  ) async {
    return versions[workoutTemplateId];
  }

  @override
  String generateWorkoutBlockId() => 'generated-block-${_idCounter++}';

  @override
  String generateExerciseSlotId() => 'generated-slot-${_idCounter++}';
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}
