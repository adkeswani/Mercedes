import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/data/workout_draft_client_id_store_contract.dart';
import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_draft_client_id.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late _MemoryDraftStore localStore;
  late ProviderContainer container;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    localStore = _MemoryDraftStore();
    await _seedWorkout(firestore);
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(
          WorkoutInstanceRepository(firestore: firestore),
        ),
        workoutTemplateRepositoryProvider.overrideWithValue(
          WorkoutTemplateRepository(firestore: firestore),
        ),
        exerciseTemplateRepositoryProvider.overrideWithValue(
          ExerciseTemplateRepository(firestore: firestore),
        ),
        workoutDraftLocalStoreProvider.overrideWithValue(localStore),
        workoutCompletionDraftRepositoryProvider.overrideWithValue(
          WorkoutCompletionDraftRepository(
            firestore: firestore,
            localStore: localStore,
          ),
        ),
        workoutDraftClientIdProvider.overrideWithValue('test-tab'),
      ],
    );
    await container.read(authStateProvider.future);
  });

  tearDown(() => container.dispose());

  Future<void> pumpScreen(WidgetTester tester, {String id = 'instance-1'}) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: WorkoutCompletionScreen(instanceId: id),
        ),
      ),
    );
  }

  testWidgets('shows explicit not-found state instead of spinning forever',
      (tester) async {
    await pumpScreen(tester, id: 'missing');
    await tester.pumpAndSettle();

    expect(find.text('Workout not found'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows unauthorized state for another athlete', (tester) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-2')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(
          WorkoutInstanceRepository(firestore: firestore),
        ),
      ],
    );
    await container.read(authStateProvider.future);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Workout unavailable'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('autosaves and restores RPE, duration, and notes after reload',
      (tester) async {
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.enterText(find.byType(TextField), 'Recovered notes');
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(8);
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('8'), findsOneWidget);
    expect(find.text('50 min'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Recovered notes',
    );
    expect(
      find.textContaining('Restored saved workout progress'),
      findsOneWidget,
    );
  });

  testWidgets('lifecycle save uses a web-safe generated client ID',
      (tester) async {
    container.dispose();
    final bounds = <int>[];
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(
          WorkoutInstanceRepository(firestore: firestore),
        ),
        workoutTemplateRepositoryProvider.overrideWithValue(
          WorkoutTemplateRepository(firestore: firestore),
        ),
        workoutDraftLocalStoreProvider.overrideWithValue(localStore),
        workoutCompletionDraftRepositoryProvider.overrideWithValue(
          WorkoutCompletionDraftRepository(
            firestore: firestore,
            localStore: localStore,
          ),
        ),
        workoutDraftClientIdGeneratorProvider.overrideWithValue(
          WorkoutDraftClientIdGenerator(
            clock: () => DateTime.utc(2026, 10, 4, 21, 10),
            randomInt: (max) {
              bounds.add(max);
              return bounds.length - 1;
            },
          ),
        ),
        workoutDraftClientIdStoreProvider.overrideWithValue(
          _MemoryClientIdStore(),
        ),
      ],
    );
    await container.read(authStateProvider.future);

    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lifecycle save');
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();

    expect(find.text('Saved'), findsOneWidget);
    expect(localStore.value?.athleteNotes, 'Lifecycle save');
    expect(
      localStore.value?.clientId,
      endsWith('-000102030405060708090a0b0c0d0e0f'),
    );
    expect(bounds, everyElement(256));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('client ID storage failure shows retryable load failure',
      (tester) async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => Stream.value(_FakeUser('athlete-1')),
        ),
        workoutInstanceRepositoryProvider.overrideWithValue(
          WorkoutInstanceRepository(firestore: firestore),
        ),
        workoutTemplateRepositoryProvider.overrideWithValue(
          WorkoutTemplateRepository(firestore: firestore),
        ),
        workoutDraftLocalStoreProvider.overrideWithValue(localStore),
        workoutCompletionDraftRepositoryProvider.overrideWithValue(
          WorkoutCompletionDraftRepository(
            firestore: firestore,
            localStore: localStore,
          ),
        ),
        workoutDraftClientIdStoreProvider.overrideWithValue(
          _ThrowingClientIdStore(),
        ),
      ],
    );
    await container.read(authStateProvider.future);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Could not load workout'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.textContaining('session storage unavailable'), findsOneWidget);
    expect(localStore.value, isNull);
  });

  testWidgets(
      'root recreation in one tab restores lifecycle save without conflict',
      (tester) async {
    container.dispose();
    final clientIdStore = _MemoryClientIdStore();
    final generator = WorkoutDraftClientIdGenerator(
      clock: () => DateTime.utc(2026, 10, 4, 21, 10),
      randomInt: (_) => 0xab,
    );

    ProviderContainer createContainer() {
      return ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => Stream.value(_FakeUser('athlete-1')),
          ),
          workoutInstanceRepositoryProvider.overrideWithValue(
            WorkoutInstanceRepository(firestore: firestore),
          ),
          workoutTemplateRepositoryProvider.overrideWithValue(
            WorkoutTemplateRepository(firestore: firestore),
          ),
          workoutDraftLocalStoreProvider.overrideWithValue(localStore),
          workoutCompletionDraftRepositoryProvider.overrideWithValue(
            WorkoutCompletionDraftRepository(
              firestore: firestore,
              localStore: localStore,
            ),
          ),
          workoutDraftClientIdStoreProvider.overrideWithValue(clientIdStore),
          workoutDraftClientIdGeneratorProvider.overrideWithValue(generator),
        ],
      );
    }

    container = createContainer();
    await container.read(authStateProvider.future);
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lifecycle recreation');
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    final originalClientId = localStore.value?.clientId;
    expect(originalClientId, isNotNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    container = createContainer();
    await container.read(authStateProvider.future);
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(localStore.value?.clientId, originalClientId);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Lifecycle recreation',
    );
    expect(find.textContaining('another'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('newer same-tab lifecycle revision restores normally',
      (tester) async {
    final repository = WorkoutCompletionDraftRepository(
      firestore: firestore,
      localStore: localStore,
    );
    await repository.save(
      _draftForTest(
        revision: 2,
        clientId: 'test-tab',
        notes: 'Newest lifecycle notes',
      ),
    );
    localStore.value = _draftForTest(
      revision: 1,
      clientId: 'test-tab',
      notes: 'Older local snapshot',
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Newest lifecycle notes',
    );
    expect(find.text('Restored saved workout progress.'), findsOneWidget);
    expect(find.textContaining('another'), findsNothing);
  });

  testWidgets('newer different-tab revision retains conflict disclosure',
      (tester) async {
    final repository = WorkoutCompletionDraftRepository(
      firestore: firestore,
      localStore: localStore,
    );
    await repository.save(
      _draftForTest(
        revision: 2,
        clientId: 'other-tab',
        notes: 'Other tab notes',
      ),
    );
    localStore.value = _draftForTest(
      revision: 1,
      clientId: 'test-tab',
      notes: 'Current tab notes',
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'Other tab notes',
    );
    expect(find.textContaining('another device or tab'), findsOneWidget);
  });

  testWidgets('renders a completed workout as immutable details',
      (tester) async {
    await firestore.collection('workoutInstances').doc('instance-1').update({
      'status': 'completed',
      'completedAt': DateTime.utc(2026, 10, 4, 13),
      'rpe': 9,
      'durationMinutes': 65,
      'athleteNotes': 'Done',
    });

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Workout Details'), findsOneWidget);
    expect(find.text('Completion Details'), findsOneWidget);
    expect(find.textContaining('Duration: 65 min'), findsOneWidget);
    expect(find.text('Mark as Completed'), findsNothing);
  });

  testWidgets('direct-route completion returns to the athlete workspace',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/athlete/workouts/instance-1',
      routes: [
        GoRoute(
          path: '/athlete/today',
          builder: (_, __) => const Scaffold(body: Text('Athlete Today')),
        ),
        GoRoute(
          path: '/athlete/workouts/:instanceId',
          builder: (_, state) => WorkoutCompletionScreen(
            instanceId: state.pathParameters['instanceId']!,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.text('Mark as Completed'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .whereType<String>()
          .join(' | '),
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();

    expect(find.text('Athlete Today'), findsOneWidget);
    expect(
      (await firestore.collection('workoutInstances').doc('instance-1').get())
          .data()?['status'],
      'completed',
    );
    expect(localStore.value, isNull);
  });

  testWidgets(
      'standard exercise card shows media/instructions by default, '
      'collapses, and records sets/reps/weight actuals',
      (tester) async {
    await _seedWorkoutWithExercises(firestore);

    await pumpScreen(tester, id: 'instance-2');
    await tester.pumpAndSettle();

    final pushupCard = find.byKey(const ValueKey('slot-pushup'));
    final instructionsInPushupCard = find.descendant(
      of: pushupCard,
      matching: find.text('Instructions'),
    );
    final setsFieldInPushupCard = find.descendant(
      of: pushupCard,
      matching: find.widgetWithText(TextField, 'Sets'),
    );

    expect(find.text('Push Up'), findsOneWidget);
    expect(find.textContaining('A basic push up.'), findsOneWidget);
    expect(find.byType(BoundedScrollableText), findsWidgets);
    expect(setsFieldInPushupCard, findsOneWidget);
    expect(find.widgetWithText(TextField, 'Reps'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Weight'), findsOneWidget);

    expect(instructionsInPushupCard, findsOneWidget);
    await tester.tap(find.byIcon(Icons.expand_less).first);
    await tester.pumpAndSettle();
    expect(instructionsInPushupCard, findsNothing);
    expect(setsFieldInPushupCard, findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more).first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Sets'), '4');
    await tester.enterText(find.widgetWithText(TextField, 'Reps'), '12');
    await tester.enterText(find.widgetWithText(TextField, 'Weight'), '60kg');
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();

    final results = await firestore
        .collection('workoutInstances')
        .doc('instance-2')
        .collection('slotResults')
        .doc('slot-pushup')
        .get();
    expect(results.data()?['sets'], 4);
    expect(results.data()?['reps'], '12');
    expect(results.data()?['weight'], '60kg');
  });

  testWidgets(
      'climbing route card shows attempts/sent inputs and records actuals',
      (tester) async {
    await _seedWorkoutWithExercises(firestore);

    await pumpScreen(tester, id: 'instance-2');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Boulder Problem'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Boulder Problem'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Attempts'), findsOneWidget);
    expect(find.text('Sent the route'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Attempts'), '5');
    await tester.tap(find.text('Sent the route'));
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();

    final results = await firestore
        .collection('workoutInstances')
        .doc('instance-2')
        .collection('slotResults')
        .doc('slot-boulder')
        .get();
    expect(results.data()?['attempts'], 5);
    expect(results.data()?['sent'], true);
  });

  testWidgets(
      'timed exercise work timer counts down and fills in duration; rest '
      'timer records restSeconds', (tester) async {
    await _seedWorkoutWithExercises(firestore);

    await pumpScreen(tester, id: 'instance-2');
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Plank Hold'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final workTimer = find.byKey(const ValueKey('work-timer-slot-plank'));
    final restTimer = find.byKey(const ValueKey('rest-timer-slot-plank'));
    expect(workTimer, findsOneWidget);
    expect(restTimer, findsOneWidget);
    expect(
      find.descendant(of: workTimer, matching: find.text('0:30')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: restTimer, matching: find.text('0:15')),
      findsOneWidget,
    );

    // Starting the work timer ticks down and fills in the duration field.
    final workTimerState =
        tester.state<WorkoutTimerWidgetState>(workTimer);
    workTimerState.start();
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.descendant(of: workTimer, matching: find.text('0:27')),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TextField, 'Duration (seconds)'),
      findsOneWidget,
    );
    final durationField = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Duration (seconds)'),
    );
    expect(durationField.controller?.text, '3');

    // Pausing stops the countdown.
    workTimerState.pause();
    await tester.pump(const Duration(seconds: 3));
    expect(
      find.descendant(of: workTimer, matching: find.text('0:27')),
      findsOneWidget,
    );

    // Starting the rest timer records the elapsed restSeconds onto the
    // actual once the workout is completed.
    final restTimerState =
        tester.state<WorkoutTimerWidgetState>(restTimer);
    restTimerState.start();
    await tester.pump(const Duration(seconds: 5));
    restTimerState.pause();
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Mark as Completed'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();

    final results = await firestore
        .collection('workoutInstances')
        .doc('instance-2')
        .collection('slotResults')
        .doc('slot-plank')
        .get();
    expect(results.data()?['durationSeconds'], 3);
    expect(results.data()?['restSeconds'], 5);
  });
}

WorkoutCompletionDraft _draftForTest({
  required int revision,
  required String clientId,
  required String notes,
}) {
  return WorkoutCompletionDraft(
    instanceId: 'instance-1',
    athleteId: 'athlete-1',
    rpe: 6,
    durationMinutes: 45,
    athleteNotes: notes,
    revision: revision,
    clientId: clientId,
    updatedAt: DateTime.utc(2026, 10, 4, 12, revision),
    sourceRoute: '/athlete/workouts/instance-1',
  );
}

Future<void> _seedWorkout(FakeFirebaseFirestore firestore) async {
  final now = DateTime.utc(2026, 10, 4, 12);
  await firestore.collection('workoutInstances').doc('instance-1').set({
    'programId': 'program-1',
    'athleteId': 'athlete-1',
    'workoutTemplateId': 'workout-1',
    'workoutTemplateVersion': 1,
    'scheduledDate': '2026-10-04',
    'assignedBy': 'trainer-1',
    'assignedAt': now,
    'status': 'scheduled',
    'workoutType': 'push',
    'createdAt': now,
    'updatedAt': now,
  });
  await firestore
      .collection('workoutTemplates')
      .doc('workout-1')
      .collection('workoutTemplateVersions')
      .doc('1')
      .set({
    'versionNumber': 1,
    'publishedAt': now,
    'exercises': <Map<String, dynamic>>[],
  });
}

/// Seeds a second workout instance with a standard exercise block and a
/// climbing route block (each backed by a published exercise template),
/// used by tests exercising the exercise-card media/instructions and
/// mode-aware actual-recording UI.
Future<void> _seedWorkoutWithExercises(FakeFirebaseFirestore firestore) async {
  final now = DateTime.utc(2026, 10, 4, 12);
  await firestore.collection('workoutInstances').doc('instance-2').set({
    'programId': 'program-1',
    'athleteId': 'athlete-1',
    'workoutTemplateId': 'workout-2',
    'workoutTemplateVersion': 1,
    'scheduledDate': '2026-10-04',
    'assignedBy': 'trainer-1',
    'assignedAt': now,
    'status': 'scheduled',
    'workoutType': 'push',
    'createdAt': now,
    'updatedAt': now,
  });
  await firestore
      .collection('workoutTemplates')
      .doc('workout-2')
      .collection('workoutTemplateVersions')
      .doc('1')
      .set({
    'versionNumber': 1,
    'publishedAt': now,
    'storageFormat': 'typedWorkoutBlocksV1',
    'blocks': [
      {
        'blockId': 'block-pushup',
        'type': 'standardExercise',
        'sortOrder': 0,
        'slotIds': ['slot-pushup'],
        'slotStartOrder': 0,
        'slotCount': 1,
      },
      {
        'blockId': 'block-boulder',
        'type': 'climbingRoute',
        'sortOrder': 1,
        'slotIds': ['slot-boulder'],
        'slotStartOrder': 1,
        'slotCount': 1,
        'grade': 'V4',
        'color': 'Blue',
        'targetAttempts': 3,
      },
      {
        'blockId': 'block-plank',
        'type': 'timedInterval',
        'sortOrder': 2,
        'slotIds': ['slot-plank'],
        'slotStartOrder': 2,
        'slotCount': 1,
        'rounds': 1,
        'workSeconds': 30,
        'restSeconds': 15,
      },
    ],
    'slots': [
      {
        'slotId': 'slot-pushup',
        'blockId': 'block-pushup',
        'exerciseId': 'ex-pushup',
        'exerciseVersion': 1,
        'sortOrder': 0,
        'exerciseName': 'Push Up',
        'prescription': {'mode': 'reps', 'sets': 3, 'reps': '10'},
      },
      {
        'slotId': 'slot-boulder',
        'blockId': 'block-boulder',
        'exerciseId': 'ex-boulder',
        'exerciseVersion': 1,
        'sortOrder': 0,
        'exerciseName': 'Boulder Problem',
        'prescription': {'mode': 'reps'},
      },
      {
        'slotId': 'slot-plank',
        'blockId': 'block-plank',
        'exerciseId': 'ex-plank',
        'exerciseVersion': 1,
        'sortOrder': 0,
        'exerciseName': 'Plank Hold',
        'prescription': {'mode': 'time'},
      },
    ],
  });
  await firestore.collection('exerciseTemplates').doc('ex-pushup').set({
    'currentVersion': 1,
    'createdBy': 'trainer-1',
    'ownerId': 'trainer-1',
  });
  await firestore
      .collection('exerciseTemplates')
      .doc('ex-pushup')
      .collection('exerciseVersions')
      .doc('1')
      .set({
    'versionNumber': 1,
    'name': 'Push Up',
    'description': 'A basic push up.',
    'instructions':
        'Line one\nLine two\nLine three\nLine four\nLine five overflow',
    'publishedAt': now,
    'publishedBy': 'trainer-1',
  });
  await firestore.collection('exerciseTemplates').doc('ex-boulder').set({
    'currentVersion': 1,
    'createdBy': 'trainer-1',
    'ownerId': 'trainer-1',
  });
  await firestore
      .collection('exerciseTemplates')
      .doc('ex-boulder')
      .collection('exerciseVersions')
      .doc('1')
      .set({
    'versionNumber': 1,
    'name': 'Boulder Problem',
    'description': 'A bouldering problem on the wall.',
    'instructions': 'Climb the marked route to the top.',
    'publishedAt': now,
    'publishedBy': 'trainer-1',
  });
  await firestore.collection('exerciseTemplates').doc('ex-plank').set({
    'currentVersion': 1,
    'createdBy': 'trainer-1',
    'ownerId': 'trainer-1',
  });
  await firestore
      .collection('exerciseTemplates')
      .doc('ex-plank')
      .collection('exerciseVersions')
      .doc('1')
      .set({
    'versionNumber': 1,
    'name': 'Plank Hold',
    'description': 'Hold a plank position.',
    'instructions': 'Keep the body straight.',
    'publishedAt': now,
    'publishedBy': 'trainer-1',
  });
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}

class _MemoryDraftStore implements WorkoutDraftLocalStore {
  WorkoutCompletionDraft? value;

  @override
  Future<void> delete(String instanceId) async {
    value = null;
  }

  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async => value;

  @override
  Future<void> write(WorkoutCompletionDraft draft) async {
    value = draft;
  }
}

class _MemoryClientIdStore implements WorkoutDraftClientIdStore {
  String? value;

  @override
  String? read() => value;

  @override
  void write(String clientId) {
    value = clientId;
  }
}

class _ThrowingClientIdStore implements WorkoutDraftClientIdStore {
  @override
  String? read() => throw StateError('session storage unavailable');

  @override
  void write(String clientId) =>
      throw StateError('session storage unavailable');
}
