import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/library/domain/library_metadata.dart';
import 'package:stage5/features/library/presentation/library_providers.dart';
import 'package:stage5/features/relationships/presentation/trainer_client_relationship_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_builder_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_delete_command.dart';
import 'package:stage5/features/workouts/presentation/workout_list_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  testWidgets('confirmed swipe removes a grouped workout without getting stuck',
      (tester) async {
    final repository = _RecordingWorkoutRepository();
    final workout = _workout(
      id: 'grouped-workout',
      name: 'Grouped Workout',
      folderId: 'folder-1',
      clientAthleteId: 'athlete-1',
    );

    await tester.pumpWidget(
      _listHarness(repository: repository, workouts: [workout]),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('workout-grouped-workout')),
      findsOneWidget,
    );
    expect(find.text('Workout Folder (1)'), findsOneWidget);

    await _swipeWorkout(tester, 'Grouped Workout');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.softDeleteCalls, 1);
    expect(find.text('Grouped Workout'), findsNothing);
    expect(find.text('Workout Folder (0)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled swipe returns the workout to its original position',
      (tester) async {
    final repository = _RecordingWorkoutRepository();

    await tester.pumpWidget(
      _listHarness(
        repository: repository,
        workouts: [_workout(id: 'cancel', name: 'Cancel Workout')],
      ),
    );
    await tester.pumpAndSettle();
    final originalLeft = tester.getTopLeft(find.text('Cancel Workout')).dx;

    await _swipeWorkout(tester, 'Cancel Workout');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('Cancel Workout')).dx, originalLeft);
    expect(repository.referenceCalls, 0);
    expect(repository.softDeleteCalls, 0);
  });

  testWidgets('failed swipe rolls back and reports an actionable error',
      (tester) async {
    final repository = _RecordingWorkoutRepository(
      deleteError: StateError('permission denied'),
    );

    await tester.pumpWidget(
      _listHarness(
        repository: repository,
        workouts: [_workout(id: 'failure', name: 'Failure Workout')],
      ),
    );
    await tester.pumpAndSettle();

    await _swipeWorkout(tester, 'Failure Workout');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Failure Workout'), findsOneWidget);
    expect(
      find.textContaining('Could not delete Failure Workout'),
      findsOneWidget,
    );
    expect(repository.softDeleteCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-use workout rolls back with repository-standard guidance',
      (tester) async {
    final repository = _RecordingWorkoutRepository(referenced: true);

    await tester.pumpWidget(
      _listHarness(
        repository: repository,
        workouts: [_workout(id: 'used', name: 'Used Workout')],
      ),
    );
    await tester.pumpAndSettle();

    await _swipeWorkout(tester, 'Used Workout');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Used Workout'), findsOneWidget);
    expect(
      find.text('Cannot delete - this workout is used in a program.'),
      findsOneWidget,
    );
    expect(repository.softDeleteCalls, 0);
  });

  testWidgets('editor cancel leaves workout intact', (tester) async {
    final repository = _RecordingWorkoutRepository();
    final workout = _workout(id: 'editor-cancel', name: 'Editor Cancel');

    await tester.pumpWidget(
      _editorHarness(repository: repository, workout: workout),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Workout Builder'), findsOneWidget);
    expect(repository.referenceCalls, 0);
    expect(repository.softDeleteCalls, 0);
  });

  testWidgets('editor disables delete while shared command is pending',
      (tester) async {
    final pendingReference = Completer<bool>();
    final repository = _RecordingWorkoutRepository(
      pendingReference: pendingReference,
    );
    final workout = _workout(id: 'editor-pending', name: 'Editor Pending');

    await tester.pumpWidget(
      _editorHarness(repository: repository, workout: workout),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WorkoutBuilderScreen)),
    );
    final firstDelete = container
        .read(workoutDeleteControllerProvider.notifier)
        .delete(workoutId: workout.id, userId: 'trainer-1');
    await tester.pump();

    expect(repository.referenceCalls, 1);
    expect(repository.softDeleteCalls, 0);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNull,
    );
    final duplicate = await container
        .read(workoutDeleteControllerProvider.notifier)
        .delete(workoutId: workout.id, userId: 'trainer-1');
    expect(duplicate.status, WorkoutDeleteStatus.alreadyPending);
    expect(repository.referenceCalls, 1);
    expect(repository.softDeleteCalls, 0);

    pendingReference.complete(false);
    expect((await firstDelete).status, WorkoutDeleteStatus.deleted);
    await tester.pump();

    expect(repository.softDeleteCalls, 1);
    expect(find.text('Workout Builder'), findsOneWidget);
  });

  testWidgets('confirmed editor delete navigates safely', (tester) async {
    final repository = _RecordingWorkoutRepository();
    final workout = _workout(id: 'editor-success', name: 'Editor Success');

    await tester.pumpWidget(
      _editorHarness(repository: repository, workout: workout),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete workout'));
    await tester.pumpAndSettle();
    final confirmDelete = find.widgetWithText(FilledButton, 'Delete');
    expect(confirmDelete, findsOneWidget);
    await tester.tap(confirmDelete);
    await tester.pumpAndSettle();
    expect(find.text('Delete workout template?'), findsNothing);
    for (var i = 0; i < 5 && repository.softDeleteCalls == 0; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(repository.referenceCalls, 1);
    expect(repository.softDeleteCalls, 1);
    expect(find.text('Workout library destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editor delete failure stays visible and can be retried',
      (tester) async {
    final repository = _RecordingWorkoutRepository(
      deleteError: StateError('ownership mismatch'),
    );
    final workout = _workout(id: 'editor-failure', name: 'Editor Failure');

    await tester.pumpWidget(
      _editorHarness(repository: repository, workout: workout),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Workout Builder'), findsOneWidget);
    expect(
      find.textContaining('Could not delete Editor Failure'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _swipeWorkout(WidgetTester tester, String name) async {
  await tester.drag(find.text(name), const Offset(-700, 0));
  await tester.pumpAndSettle();
  expect(find.text('Delete workout template?'), findsOneWidget);
}

Widget _listHarness({
  required _RecordingWorkoutRepository repository,
  required List<WorkoutTemplate> workouts,
}) {
  final timestamp = DateTime.utc(2026);
  final folder = LibraryFolder(
    id: 'folder-1',
    ownerId: 'trainer-1',
    name: 'Workout Folder',
    itemType: LibraryItemType.workout,
    createdAt: timestamp,
    createdBy: 'trainer-1',
    updatedAt: timestamp,
    updatedBy: 'trainer-1',
  );
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream.value(_FakeUser('trainer-1')),
      ),
      workoutTemplateRepositoryProvider.overrideWithValue(repository),
      workoutTemplatesProvider.overrideWith((ref) => Stream.value(workouts)),
      libraryFoldersProvider(LibraryItemType.workout).overrideWith(
        (ref) => Stream.value([folder]),
      ),
      activeTrainerClientNamesProvider.overrideWith(
        (ref) async => const {'athlete-1': 'Alex Athlete'},
      ),
    ],
    child: const MaterialApp(home: WorkoutListScreen()),
  );
}

Widget _editorHarness({
  required _RecordingWorkoutRepository repository,
  required WorkoutTemplate workout,
}) {
  final router = GoRouter(
    initialLocation: '/workouts/${workout.id}',
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
      workoutTemplateRepositoryProvider.overrideWithValue(repository),
      workoutTemplatesProvider.overrideWith((ref) => Stream.value([workout])),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

WorkoutTemplate _workout({
  required String id,
  required String name,
  String? folderId,
  String? clientAthleteId,
}) {
  final timestamp = DateTime.utc(2026);
  return WorkoutTemplate(
    id: id,
    ownerId: 'trainer-1',
    name: name,
    workoutType: WorkoutType.fullBody,
    currentVersion: 0,
    createdAt: timestamp,
    createdBy: 'trainer-1',
    updatedAt: timestamp,
    updatedBy: 'trainer-1',
    folderId: folderId,
    clientAthleteId: clientAthleteId,
  );
}

class _RecordingWorkoutRepository extends WorkoutTemplateRepository {
  _RecordingWorkoutRepository({
    this.referenced = false,
    this.deleteError,
    this.pendingReference,
  }) : super(firestore: FakeFirebaseFirestore());

  final bool referenced;
  final Object? deleteError;
  final Completer<bool>? pendingReference;
  int referenceCalls = 0;
  int softDeleteCalls = 0;

  @override
  Future<WorkoutTemplate?> getById(String id) async =>
      _workout(id: id, name: id.startsWith('editor-') ? _editorName(id) : id);

  @override
  Future<bool> isWorkoutReferenced(String workoutTemplateId) async {
    referenceCalls++;
    if (pendingReference != null) {
      return pendingReference!.future;
    }
    return referenced;
  }

  @override
  Future<void> softDelete(String id, String userId) async {
    softDeleteCalls++;
    if (deleteError != null) {
      throw deleteError!;
    }
  }

  String _editorName(String id) {
    return id
        .split('-')
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}
