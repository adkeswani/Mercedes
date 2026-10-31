import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/exercises/presentation/exercise_media_widgets.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/data/workout_draft_local_store_contract.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProviderContainer container;
  late _MemoryStore store;
  final circuit = ClimbingCircuitBlock(
    blockId: 'circuit',
    sortOrder: 0,
    videoUrl: 'https://example.test/circuit-drill.mp4',
    exercise: ExerciseSlot(
        slotId: 'circuit-slot',
        exerciseId: 'exercise',
        exerciseName: 'Climbing practice',
        sortOrder: 0,
        mode: ExerciseMode.reps),
    rows: const [
      ClimbingCircuitRow(
          rowId: 'row-1',
          gradingSystem: ClimbingGradingSystem.vScale,
          grade: 'V2',
          climbs: 3,
          maxAttemptsPerClimb: 2,
          notes: 'Technique'),
    ],
  );
  final free = FreeClimbingBlock(
    blockId: 'free',
    sortOrder: 1,
    slotId: 'free-slot',
    notes: 'Explore routes',
    videoUrl: 'https://example.test/free-drill.mp4',
  );

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    store = _MemoryStore();
    final templates = WorkoutTemplateRepository(firestore: firestore);
    await firestore
        .collection('exerciseTemplates')
        .doc('exercise')
        .set({'createdBy': 'trainer', 'currentVersion': 2});
    for (final version in [1, 2]) {
      await firestore
          .collection('exerciseTemplates')
          .doc('exercise')
          .collection('exerciseVersions')
          .doc('$version')
          .set({
        'versionNumber': version,
        'name': 'Climbing practice',
        'instructions': version == 1
            ? 'Pinned climbing instruction'
            : 'Newer instruction must not replace history',
        'publishedAt': DateTime.utc(2026, 10, 31),
        'publishedBy': 'trainer',
      });
    }
    await firestore.collection('workoutTemplates').doc('workout').set({
      'createdBy': 'trainer',
      'ownerId': 'trainer',
      'currentVersion': 0,
    });
    await templates.publishVersion(
        templateId: 'workout', userId: 'trainer', blocks: [circuit, free]);
    await firestore.collection('workoutInstances').doc('instance').set({
      'programId': 'program',
      'athleteId': 'athlete',
      'assignedBy': 'trainer',
      'workoutTemplateId': 'workout',
      'workoutTemplateVersion': 1,
      'scheduledDate': '2026-10-31',
      'status': 'scheduled',
      'actualsStorageFormat': 'slotResultsSubcollection',
      'actualSlotIds': <String>[],
    });
    container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => Stream.value(_User('athlete'))),
      workoutTemplateRepositoryProvider.overrideWithValue(templates),
      exerciseTemplateRepositoryProvider
          .overrideWithValue(ExerciseTemplateRepository(firestore: firestore)),
      workoutInstanceRepositoryProvider
          .overrideWithValue(WorkoutInstanceRepository(firestore: firestore)),
      workoutCompletionDraftRepositoryProvider.overrideWithValue(
          WorkoutCompletionDraftRepository(
              firestore: firestore, localStore: store)),
      workoutDraftLocalStoreProvider.overrideWithValue(store),
      workoutDraftClientIdProvider.overrideWithValue('climbing-test-tab'),
    ]);
    await container.read(authStateProvider.future);
  });
  tearDown(() => container.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    final router =
        GoRouter(initialLocation: '/athlete/workouts/instance', routes: [
      GoRoute(
          path: '/athlete/workouts/:id',
          builder: (_, __) =>
              const WorkoutCompletionScreen(instanceId: 'instance')),
      GoRoute(
          path: '/athlete/today',
          builder: (_, __) => const Scaffold(body: Text('Done'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> complete(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Mark as Completed'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as Completed'));
    await tester.pumpAndSettle();
  }

  Future<void> expectVideos(WidgetTester tester) async {
    for (final entry in {
      'circuit': 'https://example.test/circuit-drill.mp4',
      'free': 'https://example.test/free-drill.mp4',
    }.entries) {
      final finder = find.byKey(ValueKey('climbing-video-${entry.key}'));
      await tester.scrollUntilVisible(finder, 250,
          scrollable: find.byType(Scrollable).first);
      expect(tester.widget<ExerciseVideoPreview>(finder).url, entry.value);
    }
  }

  testWidgets(
      'circuit checkbox records pinned row and free rows remain optional',
      (tester) async {
    await pumpScreen(tester);
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('Pinned climbing instruction'), findsOneWidget);
    expect(
        find.text('Newer instruction must not replace history'), findsNothing);
    expect(find.text('Attempts'), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final rpe = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>).first);
    rpe.onChanged!(8);
    await complete(tester);
    expect(find.text('Done'), findsOneWidget);
    final instance = (await WorkoutInstanceRepository(firestore: firestore)
        .getById('instance'))!;
    expect(
        instance.actualsBySlot['circuit-slot']!.circuitRows!.single.completed,
        isTrue);
    expect(instance.actualsBySlot['circuit-slot']!.circuitRows!.single.rowId,
        'row-1');
    expect(instance.actualsBySlot['circuit-slot']!.circuitRows!.single.rpe, 8);
    expect(instance.actualsBySlot['free-slot']!.freeRows, isEmpty);
  });

  testWidgets(
      'free climbing result rows validate counts and persist canonical grades',
      (tester) async {
    await pumpScreen(tester);
    final add = find.text('Add result row');
    await tester.scrollUntilVisible(add, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    final count = find.widgetWithText(TextFormField, 'Climbs completed');
    await tester.scrollUntilVisible(count, -250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(count, '0');
    await tester.pump();
    expect(find.text('Enter a positive whole number'), findsOneWidget);
    await complete(tester);
    expect(find.textContaining('positive whole number of climbs completed'),
        findsOneWidget);
    expect(
        (await WorkoutInstanceRepository(firestore: firestore)
                .getById('instance'))!
            .isScheduled,
        isTrue);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final serverDraft = firestore
        .collection('workoutInstances')
        .doc('instance')
        .collection('completionDrafts')
        .doc('current');
    expect((await serverDraft.get()).exists, isTrue);
    expect((await serverDraft.collection('climbingInputs').get()).docs,
        hasLength(2));
    await tester.ensureVisible(count);
    await tester.enterText(count, '2');
    await tester.pump();
    await complete(tester);
    final instance = (await WorkoutInstanceRepository(firestore: firestore)
        .getById('instance'))!;
    expect(instance.actualsBySlot['free-slot']!.freeRows!.single.climbs, 2);
    expect(instance.actualsBySlot['free-slot']!.freeRows!.single.grade, 'V0');
    expect(instance.actualsBySlot['free-slot']!.attempts, isNull);
    expect((await serverDraft.get()).exists, isFalse);
    expect(
        (await serverDraft.collection('climbingInputs').get()).docs, isEmpty);
  });

  testWidgets(
      'autosave and reload preserve climbing checkbox, RPE, rows and notes',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(Checkbox));
    final add = find.text('Add result row');
    await tester.scrollUntilVisible(add, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    final count = find.widgetWithText(TextFormField, 'Climbs completed');
    await tester.scrollUntilVisible(count, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(count, '4');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Row note (optional)').last,
        'Recovered row');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.scrollUntilVisible(count, 250,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextFormField>(count).initialValue, '4');
    expect(
        tester
            .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Row note (optional)').last)
            .initialValue,
        'Recovered row');
    final restored = store.draft!;
    expect(
        restored.slotInputs['free-slot']!['freeRows'][0]['rowId'], isNotEmpty);
  });

  testWidgets(
      'completed detail displays immutable prescription and actual row results',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(Checkbox));
    final rpe = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>).first);
    rpe.onChanged!(9);
    await complete(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    expect(find.text('Workout Details'), findsOneWidget);
    expect(find.text('Pinned climbing instruction'), findsOneWidget);
    expect(find.text('3 × V2 · Max 2 attempts per climb'), findsOneWidget);
    expect(find.text('Completed · RPE 9'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Add result row'), findsNothing);
  });

  testWidgets(
      'can remove an optional unfinished free climbing row before completing',
      (tester) async {
    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Add result row'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add result row'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove result row'));
    await tester.tap(find.text('Remove result row'));
    await tester.pumpAndSettle();
    await complete(tester);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('drill videos display through recovery and pinned history',
      (tester) async {
    await pumpScreen(tester);
    await expectVideos(tester);
    await tester.scrollUntilVisible(find.byType(Checkbox), -250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    await expectVideos(tester);
    await complete(tester);
    expect(find.text('Done'), findsOneWidget);
    await container.read(workoutTemplateRepositoryProvider).publishVersion(
      templateId: 'workout',
      userId: 'trainer',
      blocks: [
        ClimbingCircuitBlock(
          blockId: circuit.blockId,
          sortOrder: 0,
          exercise: circuit.exercise,
          rows: circuit.rows,
          videoUrl: 'https://example.test/new-drill.mp4',
        ),
        FreeClimbingBlock(
          blockId: free.blockId,
          sortOrder: 1,
          slotId: free.slots.single.slotId,
        ),
      ],
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpScreen(tester);
    expect(find.text('Workout Details'), findsOneWidget);
    await expectVideos(tester);
  });
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _MemoryStore implements WorkoutDraftLocalStore {
  WorkoutCompletionDraft? draft;
  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async => draft;
  @override
  Future<void> write(WorkoutCompletionDraft value) async {
    draft = WorkoutCompletionDraft.fromMap(value.toLocalMap());
  }

  @override
  Future<void> delete(String instanceId) async => draft = null;
}
