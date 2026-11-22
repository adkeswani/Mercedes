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
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_builder_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  testWidgets('builder offers explicit climbing workout types', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = FakeFirebaseFirestore();
    final repository = _VersionedWorkoutRepository(firestore: db);
    final id = await repository.create(
      name: 'Builder Workout',
      workoutType: WorkoutType.fullBody,
      userId: 'trainer-1',
    );
    await tester.pumpWidget(_harness(
      repository: repository,
      workout: _workout(id: id, currentVersion: 0),
    ));
    await tester.pumpAndSettle();
    final dropdown = find.byType(DropdownButton<WorkoutType>);
    for (final type in [
      WorkoutType.climbingPower,
      WorkoutType.climbingEndurance,
      WorkoutType.climbingConditioning,
      WorkoutType.climbingLimit,
    ]) {
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(type.label).last);
      await tester.tap(find.text(type.label).last);
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<WorkoutType>>(dropdown).value, type);
      expect(
        (await db.collection('workoutTemplates').doc(id).get())
            .data()!['workoutType'],
        type.name,
      );
    }
  });

  testWidgets('builder exercises have larger padding and separation',
      (tester) async {
    final repo = _VersionedWorkoutRepository();
    final workout = _workout(id: 'spaced-workout', currentVersion: 1);
    repo.versions[workout.id] = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.utc(2026),
      blocks: [
        StandardExerciseBlock(
          blockId: 'spaced-block',
          sortOrder: 0,
          exercise: ExercisePrescription(
            slotId: 'spaced-slot',
            sortOrder: 0,
            exerciseId: 'ex-bike',
            exerciseVersion: 1,
            exerciseName: 'Bike',
            mode: ExerciseMode.reps,
          ),
        ),
      ],
    );
    await tester.pumpWidget(_harness(repository: repo, workout: workout));
    await tester.pumpAndSettle();
    final tile = find.widgetWithText(ListTile, 'Bike');
    expect(tester.widget<ListTile>(tile).contentPadding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
    expect(
        tester
            .widget<Card>(find.ancestor(of: tile, matching: find.byType(Card)))
            .margin,
        const EdgeInsets.only(bottom: 24));
  });

  testWidgets('Add menu omits legacy climbing route', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Standard Exercise'), findsOneWidget);
    expect(find.text('Timed Interval'), findsOneWidget);
    expect(find.text('Circuit'), findsOneWidget);
    expect(find.text('Climbing Route'), findsNothing);
    expect(find.text('AMRAP'), findsOneWidget);
    expect(find.text('Climbing Circuit'), findsOneWidget);
    expect(find.text('Free Climbing'), findsOneWidget);
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

  testWidgets('legacy climbing route remains editable', (tester) async {
    final repo = _VersionedWorkoutRepository();
    repo.versions['legacy'] = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.utc(2026),
      blocks: [
        ClimbingRouteBlock(
          blockId: 'route',
          sortOrder: 0,
          route: ExerciseSlot(
              slotId: 'route-slot',
              exerciseId: 'ex-route',
              exerciseName: 'Overhang Route',
              sortOrder: 0,
              mode: ExerciseMode.reps),
          grade: 'V2',
          gradingSystem: ClimbingGradingSystem.vScale,
        ),
      ],
    );
    await tester.pumpWidget(_harness(
        repository: repo, workout: _workout(id: 'legacy', currentVersion: 1)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit prescription'));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(DropdownButtonFormField<String>, 'Grade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('V4').last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Color'), findsNothing);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Overhang Route'), findsOneWidget);
    expect(find.textContaining('Climbing Route · V4'), findsOneWidget);
  });

  testWidgets(
      'creates a climbing circuit, surfaces invalid counts, and edits stable rows',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Climbing Circuit'));
    await tester.tap(find.text('Climbing Circuit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach instructions (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overhang Route'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive whole number'), findsOneWidget);
    final count = find.widgetWithText(TextFormField, 'Number of climbs');
    await tester.ensureVisible(count);
    await tester.enterText(count, '3');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Max attempts per climb (optional)'),
        '2');
    expect(find.widgetWithText(TextFormField, 'Video URL (optional)'),
        findsNothing);
    expect(find.text('Choose from YouTube library'), findsNothing);
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('3 × V0 (max 2/climb)'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkoutBuilderScreen)));
    final original =
        container.read(workoutDraftProvider).single as ClimbingCircuitBlock;
    expect(original.videoUrl, isNull);
    await tester.tap(find.byTooltip('Edit prescription'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Video URL (optional)'),
        findsNothing);
    await tester.ensureVisible(count);
    await tester.enterText(count, '4');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final edited =
        container.read(workoutDraftProvider).single as ClimbingCircuitBlock;
    expect(edited.rows.single.rowId, original.rows.single.rowId);
    expect(edited.exercise.slotId, original.exercise.slotId);
    expect(edited.rows.single.climbs, 4);
    expect(edited.videoUrl, original.videoUrl);
  });

  testWidgets(
      'creates a grades-only circuit and preserves IDs when linking and removing an exercise',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Climbing Circuit'));
    await tester.tap(find.text('Climbing Circuit'));
    await tester.pumpAndSettle();
    final count = find.widgetWithText(TextFormField, 'Number of climbs');
    final work =
        find.widgetWithText(TextFormField, 'Work duration (seconds, optional)');
    final rest =
        find.widgetWithText(TextFormField, 'Rest duration (seconds, optional)');
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(count);
    await tester.enterText(count, '3');
    await tester.ensureVisible(work);
    await tester.enterText(work, '0');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive whole number'), findsOneWidget);
    await tester.ensureVisible(work);
    await tester.enterText(work, '30');
    await tester.ensureVisible(rest);
    await tester.enterText(rest, '15');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkoutBuilderScreen)));
    final original =
        container.read(workoutDraftProvider).single as ClimbingCircuitBlock;
    expect(original.hasExercise, isFalse);
    expect(original.rows.single.workSeconds, 30);
    expect(original.rows.single.restSeconds, 15);
    expect(find.textContaining('30s work'), findsOneWidget);
    for (final link in [true, false]) {
      await tester.tap(find.byTooltip('Edit prescription'));
      await tester.pumpAndSettle();
      if (link) {
        await tester.tap(find.text('Attach instructions (optional)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Overhang Route'));
      } else {
        await tester.tap(find.text('Remove instructions'));
      }
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final edited =
          container.read(workoutDraftProvider).single as ClimbingCircuitBlock;
      expect(edited.hasExercise, link);
      expect(edited.exercise.slotId, original.exercise.slotId);
      expect(edited.rows.single.toMap(), original.rows.single.toMap());
    }
  });

  testWidgets(
      'free climbing attaches shared instructions without video authoring',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Free Climbing'));
    await tester.tap(find.text('Free Climbing'));
    await tester.pumpAndSettle();
    expect(find.text('Attach instructions'), findsNothing);
    expect(find.text('Attach instructions (optional)'), findsOneWidget);
    expect(find.text('Grade'), findsNothing);
    expect(find.text('Number of climbs'), findsNothing);
    expect(find.text('Choose from YouTube library'), findsNothing);
    await tester.tap(find.text('Attach instructions (optional)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overhang Route'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Trainer note (optional)'),
        'Explore routes');
    expect(find.widgetWithText(TextFormField, 'Video URL (optional)'),
        findsNothing);
    final work =
        find.widgetWithText(TextFormField, 'Work duration (seconds, optional)');
    final rest =
        find.widgetWithText(TextFormField, 'Rest duration (seconds, optional)');
    await tester.ensureVisible(work);
    await tester.enterText(work, '30');
    await tester.ensureVisible(rest);
    await tester.enterText(rest, '15');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Overhang Route'), findsOneWidget);
    expect(find.textContaining('Explore routes'), findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkoutBuilderScreen)));
    expect(container.read(workoutDraftProvider).single.videoUrl, isNull);
    await tester.tap(find.byTooltip('Edit prescription'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove instructions'));
    await tester.tap(find.text('Remove instructions'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(container.read(workoutDraftProvider).single.videoUrl, isNull);
    final free =
        container.read(workoutDraftProvider).single as FreeClimbingBlock;
    expect(free.workSeconds, 30);
    expect(free.restSeconds, 15);
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

  testWidgets(
      '30-row circuit shares a climbing/rest cap and preserves historical video',
      (tester) async {
    final repo = _VersionedWorkoutRepository();
    repo.versions['rest-circuit'] = WorkoutTemplateVersion(
      versionNumber: 1,
      publishedAt: DateTime.utc(2026),
      blocks: [
        ClimbingCircuitBlock(
          blockId: 'circuit',
          sortOrder: 0,
          slotId: 'slot',
          videoUrl: 'https://example.test/historical.mp4',
          rows: [
            const ClimbingCircuitRow(
                rowId: 'climb',
                gradingSystem: ClimbingGradingSystem.vScale,
                grade: 'V2',
                climbs: 2),
            for (var i = 1; i < 30; i++)
              ClimbingCircuitRow.rest(rowId: 'rest-$i', durationSeconds: 15),
          ],
        ),
      ],
    );
    await tester.pumpWidget(_harness(
        repository: repo,
        workout: _workout(id: 'rest-circuit', currentVersion: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit prescription'));
    await tester.pumpAndSettle();
    for (final text in ['Add climbing row', 'Add rest row']) {
      final button = find.widgetWithText(TextButton, text);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
    }
    expect(find.widgetWithText(TextFormField, 'Video URL (optional)'),
        findsNothing);
    expect(
        tester
            .widget<ExerciseVideoPreview>(find.byType(ExerciseVideoPreview))
            .url,
        'https://example.test/historical.mp4');
    final remove = find.text('Remove rest row').first;
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    final add = find.text('Add rest row');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a positive whole number'), findsOneWidget);
    final duration =
        find.widgetWithText(TextFormField, 'Rest duration (seconds)').last;
    await tester.ensureVisible(duration);
    await tester.enterText(duration, '20');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
        tester.element(find.byType(WorkoutBuilderScreen)));
    final result =
        container.read(workoutDraftProvider).single as ClimbingCircuitBlock;
    expect(result.rows.length, 30);
    expect(result.rows.last.isRest, isTrue);
    expect(result.rows.last.restSeconds, 20);
    expect(result.rows.first.rowId, 'climb');
    expect(result.videoUrl, 'https://example.test/historical.mp4');
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
  _VersionedWorkoutRepository({FakeFirebaseFirestore? firestore})
      : super(firestore: firestore ?? FakeFirebaseFirestore());

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
