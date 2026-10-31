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
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

import '../integration_test/support/list_test_utils.dart';
import '../integration_test/support/browser_test_wait.dart';
import '../integration_test/workout_climbing_canary_test.dart' as canary;

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

  Future<void> pumpScreen(WidgetTester tester,
      {ScrollController? sidebarController}) async {
    final router =
        GoRouter(initialLocation: '/athlete/workouts/instance', routes: [
      GoRoute(
          path: '/athlete/workouts/:id',
          builder: (_, state) =>
              WorkoutCompletionScreen(instanceId: state.pathParameters['id']!)),
      GoRoute(
          path: '/athlete/today',
          builder: (_, __) => const Scaffold(body: Text('Done'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: sidebarController == null
            ? null
            : (_, child) => Row(children: [
                  SizedBox(
                    width: 120,
                    child: ListView.builder(
                      controller: sidebarController,
                      itemCount: 30,
                      itemBuilder: (_, index) =>
                          SizedBox(height: 100, child: Text('Sidebar $index')),
                    ),
                  ),
                  Expanded(child: child!),
                ]),
      ),
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

  testWidgets(
      'real completion list reveals media across large-card recycling and saves',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sidebar = ScrollController();
    addTearDown(sidebar.dispose);
    await firestore
        .collection('exerciseTemplates')
        .doc('exercise')
        .collection('exerciseVersions')
        .doc('1')
        .update({
      'videoUrl': 'https://example.test/exercise-drill.mp4',
      'description': List.filled(80, 'Pinned exercise description').join('\n'),
      'instructions': List.filled(20, 'Pinned climbing instruction').join('\n'),
    });
    await container.read(workoutTemplateRepositoryProvider).publishVersion(
      templateId: 'workout',
      userId: 'trainer',
      blocks: [
        ClimbingCircuitBlock(
          blockId: circuit.blockId,
          sortOrder: 0,
          exercise: circuit.exercise,
          videoUrl: circuit.videoUrl,
          rows: [
            ...circuit.rows,
            const ClimbingCircuitRow(
              rowId: 'row-rope',
              gradingSystem: ClimbingGradingSystem.yds,
              grade: '5.13a',
              climbs: 1,
            ),
          ],
        ),
        free,
        FreeClimbingBlock(
          blockId: 'free-optional',
          sortOrder: 2,
          slotId: 'free-optional-slot',
        ),
      ],
    );
    await firestore.collection('workoutInstances').doc('instance').update({
      'workoutTemplateVersion': 2,
    });
    await pumpScreen(tester, sidebarController: sidebar);
    final scrollable = find
        .descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.byType(Scrollable),
        )
        .first;
    final originalState = tester.state<ScrollableState>(scrollable);
    final originalPosition = originalState.position;
    final originalController = tester
        .widget<ListView>(find.byKey(WorkoutCompletionScreen.listKey))
        .controller;
    final video = find.descendant(
      of: find.byKey(WorkoutCompletionScreen.listKey),
      matching: find.byKey(const ValueKey('climbing-video-circuit')),
    );
    expect(
      find.descendant(
        of: find.byType(Scrollable).last,
        matching: find.byKey(const ValueKey('climbing-video-circuit')),
      ),
      findsNothing,
    );
    await revealListTarget(
        tester, find.text('3 × V2 · Max 2 attempts per climb'),
        scrollable: scrollable);
    tester.binding.scheduleFrameCallback((_) {
      originalPosition.jumpTo(originalPosition.maxScrollExtent);
    });
    await revealListTarget(tester, video, scrollable: scrollable);
    expect(tester.widget<ExerciseVideoPreview>(video).url, circuit.videoUrl);
    expect(tester.getSize(find.byType(ClimbingCompletionCard).first).height,
        greaterThan(originalPosition.viewportDimension * 4));

    await revealListTarget(tester, find.text('Mark as Completed'),
        scrollable: scrollable);
    expect(video, findsNothing);
    await revealListTarget(tester, video, scrollable: scrollable);
    expect(video.hitTestable(), findsOneWidget);
    final checkbox = find.descendant(
      of: find.byKey(const ValueKey<String>('row-1')),
      matching: find.byType(Checkbox),
    );
    await revealListTarget(tester, checkbox, scrollable: scrollable);
    await tester.tap(checkbox);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable), same(originalState));
    expect(originalState.position, same(originalPosition));
    expect(
      tester
          .widget<ListView>(find.byKey(WorkoutCompletionScreen.listKey))
          .controller,
      same(originalController),
    );
    await revealListTarget(tester, find.text('Mark as Completed'),
        scrollable: scrollable);
    expect(video, findsNothing);
    await revealListTarget(
        tester, find.byKey(const ValueKey('climbing-video-free')),
        scrollable: scrollable);
    expect(
      tester
          .widget<ExerciseVideoPreview>(
              find.byKey(const ValueKey('climbing-video-free')))
          .url,
      free.videoUrl,
    );
    await revealListTarget(tester, video, scrollable: scrollable);
    await revealListTarget(tester, checkbox, scrollable: scrollable);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
    expect(sidebar.offset, 0);
    await expectLater(
      () => revealListTarget(tester, find.text('Missing fixture target'),
          scrollable: scrollable, maxScrolls: 2),
      throwsA(isA<StateError>()
          .having((error) => error.message, 'bounded diagnostic',
              contains('Attempts: 2/2'))
          .having((error) => error.message, 'target diagnostic',
              contains('Missing fixture target'))
          .having((error) => error.message, 'position diagnostic',
              contains('Offset:'))),
    );
    await expectLater(
      () => revealListTarget(tester, video,
          scrollable: find.byKey(const Key('missing-list')), maxScrolls: 2),
      throwsA(isA<StateError>().having((error) => error.message,
          'scrollable diagnostic', contains('expected one Scrollable'))),
    );
  });

  testWidgets(
      'real canary selectors never scroll the workout with a popup open',
      (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sidebar = ScrollController();
    addTearDown(sidebar.dispose);
    await pumpScreen(tester, sidebarController: sidebar);
    final waits = BrowserTestWaitContext(
      identity: 'athlete',
      testFile: 'test/climbing_completion_screen_test.dart',
      artifactPath: '<widget regression>',
      currentRoute: () => '/athlete/workouts/instance',
    );
    final scrollable = find
        .descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final barrierCount = find.byType(ModalBarrier).evaluate().length;
    final movedWithPopup = <double>[];
    void recordMovement() {
      if (find.byType(ModalBarrier).evaluate().length > barrierCount) {
        movedWithPopup.add(position.pixels);
      }
    }

    position.addListener(recordMovement);
    addTearDown(() => position.removeListener(recordMovement));
    final circuitRpe = find.descendant(
      of: find.byKey(const ValueKey<String>('row-1')),
      matching: find.byType(DropdownButtonFormField<int>),
    );
    await canary.selectClimbingRpe(tester, waits, circuitRpe, 8);
    expect(tester.widget<DropdownButtonFormField<int>>(circuitRpe).initialValue,
        8);
    final freeCard = find.ancestor(
      of: find.text('Trainer note: Explore routes'),
      matching: find.byType(ClimbingCompletionCard),
    );
    final add =
        find.descendant(of: freeCard, matching: find.text('Add result row'));
    await revealListTarget(tester, add, scrollable: scrollable);
    await tester.tap(add);
    await tester.pump(const Duration(milliseconds: 400));
    final system = find.descendant(
      of: freeCard,
      matching: find.byType(DropdownButtonFormField<ClimbingGradingSystem>),
    );
    await canary.selectClimbingSystem(tester, waits, system);
    expect(
      tester
          .widget<DropdownButtonFormField<ClimbingGradingSystem>>(system)
          .initialValue,
      ClimbingGradingSystem.yds,
    );
    final grade = find.descendant(
      of: freeCard,
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await canary.selectClimbingGrade(tester, waits, grade, '5.13a');
    expect(tester.widget<DropdownButtonFormField<String>>(grade).initialValue,
        '5.13a');
    final freeRpe = find.descendant(
      of: freeCard,
      matching: find.byType(DropdownButtonFormField<int>),
    );
    await canary.selectClimbingRpe(tester, waits, freeRpe, 7);
    expect(
        tester.widget<DropdownButtonFormField<int>>(freeRpe).initialValue, 7);
    expect(movedWithPopup, isEmpty);
    expect(sidebar.offset, 0);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets(
      'changing workout reloads its own draft without carrying conflict',
      (tester) async {
    await pumpScreen(tester);
    final repository = container.read(workoutCompletionDraftRepositoryProvider);
    final other = WorkoutCompletionDraft(
      instanceId: 'instance',
      athleteId: 'athlete',
      rpe: 9,
      durationMinutes: 60,
      revision: 20,
      clientId: 'other-tab',
      updatedAt: DateTime.utc(2026, 10, 31, 12),
      sourceRoute: '/athlete/workouts/instance',
      athleteNotes: 'Authoritative other-tab notes',
      slotInputs: {
        'circuit-slot': initialClimbingInput(circuit),
        'free-slot': initialClimbingInput(free),
      },
    );
    await repository.save(other);
    final notes =
        find.widgetWithText(TextFormField, 'Climbing note (optional)').first;
    await tester.ensureVisible(notes);
    await tester.enterText(notes, 'Contested first workout edit');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(WorkoutCompletionScreen.listKey),
          matching: find.byType(Scrollable),
        )
        .first;
    await revealListTarget(tester,
        find.text('Another tab saved newer progress. Its draft was restored.'),
        scrollable: scrollable);

    final second = FreeClimbingBlock(
      blockId: 'second-free',
      sortOrder: 0,
      slotId: 'second-free-slot',
      notes: 'Second workout has no prescribed rows',
      videoUrl: 'https://example.test/second-free-drill.mp4',
    );
    await firestore.collection('workoutTemplates').doc('second-workout').set({
      'createdBy': 'trainer',
      'ownerId': 'trainer',
      'currentVersion': 0,
    });
    await container.read(workoutTemplateRepositoryProvider).publishVersion(
      templateId: 'second-workout',
      userId: 'trainer',
      blocks: [second],
    );
    await firestore.collection('workoutInstances').doc('second-instance').set({
      'programId': 'program',
      'athleteId': 'athlete',
      'assignedBy': 'trainer',
      'workoutTemplateId': 'second-workout',
      'workoutTemplateVersion': 1,
      'scheduledDate': '2026-10-31',
      'status': 'scheduled',
      'actualsStorageFormat': 'slotResultsSubcollection',
      'actualSlotIds': <String>[],
    });
    final secondInput = initialClimbingInput(second)
      ..['notes'] = 'Second draft note';
    final secondDraft = WorkoutCompletionDraft(
      instanceId: 'second-instance',
      athleteId: 'athlete',
      rpe: 4,
      durationMinutes: 30,
      revision: 30,
      clientId: 'climbing-test-tab',
      updatedAt: DateTime.utc(2026, 10, 31, 13),
      sourceRoute: '/athlete/workouts/second-instance',
      athleteNotes: 'Second workout notes',
      slotInputs: {'second-free-slot': secondInput},
    );
    await repository.save(secondDraft);
    final screen = find.byType(WorkoutCompletionScreen);
    final originalState = tester.state(screen);
    GoRouter.of(tester.element(screen)).go('/athlete/workouts/second-instance');
    await tester.pumpAndSettle();
    expect(tester.state(screen), same(originalState));
    expect(find.text('Trainer note: Second workout has no prescribed rows'),
        findsOneWidget);
    expect(
        find.textContaining('Another tab saved newer progress'), findsNothing);
    final secondNotes =
        find.widgetWithText(TextFormField, 'Climbing note (optional)');
    expect(tester.widget<TextFormField>(secondNotes).initialValue,
        'Second draft note');
    await tester.ensureVisible(secondNotes);
    await tester.enterText(secondNotes, 'Latest second workout note');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await canary.selectClimbingRpe(
      tester,
      BrowserTestWaitContext(
        identity: 'athlete',
        testFile: 'test/climbing_completion_screen_test.dart',
        artifactPath: '<workout transition regression>',
        currentRoute: () => '/athlete/workouts/second-instance',
      ),
      find.byType(DropdownButtonFormField<int>),
      6,
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final restored = await repository.load(
      instanceId: 'second-instance',
      athleteId: 'athlete',
      currentClientId: 'climbing-test-tab',
    );
    expect(restored.kind, WorkoutDraftRestoreKind.server);
    expect(restored.draft!.revision, 32);
    expect(restored.draft!.clientId, 'climbing-test-tab');
    expect(restored.draft!.slotInputs.keys, ['second-free-slot']);
    expect(
        restored.draft!.slotInputs['second-free-slot']!['freeRows'], isEmpty);
    expect(restored.draft!.slotInputs['second-free-slot']!['rpe'], 6);
    expect(restored.draft!.slotInputs['second-free-slot']!['notes'],
        'Latest second workout note');
    final firstPrimary = await firestore
        .collection('workoutInstances')
        .doc('instance')
        .collection('completionDrafts')
        .doc('current')
        .get();
    expect(firstPrimary.data()!['revision'], 20);
    expect(firstPrimary.data()!['clientId'], 'other-tab');
    final secondPrimary = await firestore
        .collection('workoutInstances')
        .doc('second-instance')
        .collection('completionDrafts')
        .doc('current')
        .get();
    final secondChild = await secondPrimary.reference
        .collection('climbingInputs')
        .doc('second-free-slot')
        .get();
    expect(secondPrimary.data()!['revision'], 32);
    expect(secondChild.data()!['revision'], 32);
    expect(secondChild.data()!['rpe'], 6);
    expect(secondChild.data()!['clientId'], 'climbing-test-tab');
    expect(secondChild.data()!['notes'], 'Latest second workout note');
    expect((await store.read('instance'))!.clientId, 'other-tab');
    expect((await store.read('second-instance'))!.revision, 32);
  });
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}

class _MemoryStore implements WorkoutDraftLocalStore {
  WorkoutCompletionDraft? draft;
  final _drafts = <String, WorkoutCompletionDraft>{};
  @override
  Future<WorkoutCompletionDraft?> read(String instanceId) async =>
      _drafts[instanceId];
  @override
  Future<void> write(WorkoutCompletionDraft value) async {
    draft = WorkoutCompletionDraft.fromMap(value.toLocalMap());
    _drafts[value.instanceId] = draft!;
  }

  @override
  Future<void> delete(String instanceId) async {
    _drafts.remove(instanceId);
    if (draft?.instanceId == instanceId) draft = null;
  }
}
