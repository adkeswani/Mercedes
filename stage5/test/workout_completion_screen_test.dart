import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
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

  testWidgets('client ID storage failure shows retryable save failure',
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
    await tester.enterText(find.byType(TextField), 'Unsaved notes');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Save failed'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
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
