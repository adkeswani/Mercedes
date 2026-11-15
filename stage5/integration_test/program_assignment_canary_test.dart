import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/data/exercise_template_repository.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/program.dart';
import 'package:stage5/features/workouts/data/workout_completion_draft_repository.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_completion_draft.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';

const _testFile = 'integration_test/program_assignment_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

/// Deterministic assignable program and athlete seeded by
/// tool/run-browser-login-smoke.ps1.
const _seededProgramId = 'browser-athlete-program';
const _seededAthleteUsername = 'browser_smoke_athlete';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var initialized = false;
  Future<void> startApp(
    WidgetTester tester,
    BrowserTestWaitContext waits,
  ) async {
    if (!initialized) {
      await waits.runStep(
        'initialize Firebase emulators',
        app.initializeMercedesApp,
        timeout: const Duration(seconds: 30),
      );
      initialized = true;
    }
    await waits.runStep(
      'pump application',
      () => tester.pumpWidget(const ProviderScope(child: MercedesApp())),
    );
    await waits.waitForCondition(
      condition: 'authenticated entry or local emulator login',
      isSatisfied: () =>
          find.byKey(authenticatedAppEntryKey).evaluate().isNotEmpty ||
          find.byKey(browserSmokeLoginButtonKey).evaluate().isNotEmpty,
      pump: () => tester.pump(const Duration(milliseconds: 100)),
    );
    if (find.byKey(browserSmokeLoginButtonKey).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(browserSmokeLoginButtonKey));
    }
    await _waitFor(tester, waits, find.byKey(authenticatedAppEntryKey),
        step: 'authenticated workspace', timeout: const Duration(seconds: 30));
  }

  testWidgets(
    'trainer assigns a program to an athlete for the first time (happy path)',
    (tester) async {
      final waits = BrowserTestWaitContext(
        identity: browserSmokeConfig.identityRole?.name ?? 'unconfigured',
        testFile: _testFile,
        artifactPath: _artifactPath,
        currentRoute: () => _currentRoute(tester),
      );
      await startApp(tester, waits);

      // Regression coverage for: assigning a program to an enrolled athlete
      // used to fail on the very first attempt with "Missing or insufficient
      // permissions" because the athleteProgramInstances get rule
      // dereferenced resource.data for the brand-new instance id that
      // WorkoutInstanceRepository.assignProgram() always checks for a prior
      // idempotent assignment before writing anything. This test drives the
      // exact repository call a trainer's "Assign Program" action makes.
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(authenticatedAppEntryKey)),
      );
      final trainerUid = container.read(authStateProvider).value?.uid;
      expect(
        trainerUid,
        isNotNull,
        reason: 'Trainer must be signed in before assigning a program.',
      );
      final athleteProfile = await waits.runStep(
        'look up deterministic athlete profile',
        () => container
            .read(userProfileRepositoryProvider)
            .getUserByUsername(_seededAthleteUsername),
      );
      expect(
        athleteProfile,
        isNotNull,
        reason: 'Seeded athlete profile must exist for this canary.',
      );
      final athleteUid = athleteProfile!.uid;

      final startDate = DateTime.now()
          .add(const Duration(days: 1))
          .toIso8601String()
          .split('T')
          .first;

      final appContext = tester.element(find.byKey(authenticatedAppEntryKey));
      GoRouter.of(appContext).push(
        '/assign?programId=$_seededProgramId&athleteId=$athleteUid'
        '&mode=program&date=$startDate',
      );
      await _waitFor(
        tester,
        waits,
        find.text('Assign Program'),
        step: 'program assignment screen (fixed program and athlete)',
        timeout: const Duration(seconds: 20),
      );

      await waits.runStep(
        'submit program assignment',
        () => tester.tap(find.text('Assign Program')),
      );
      await _waitFor(
        tester,
        waits,
        find.textContaining('Assigned'),
        step: 'assignment success snackbar (no permission error)',
        timeout: const Duration(seconds: 20),
      );
      expect(
        find.textContaining('permission'),
        findsNothing,
        reason: 'A permission-denied error indicates the assignment '
            'regression has returned.',
      );

      final matches = await waits.runStep(
        'verify athlete program instance created in Firestore',
        () => FirebaseFirestore.instance
            .collection('athleteProgramInstances')
            .where('assigningTrainerId', isEqualTo: trainerUid)
            .where('athleteOwnerId', isEqualTo: athleteUid)
            .where('status', isEqualTo: 'active')
            .where('sourceProgramId', isEqualTo: _seededProgramId)
            .limit(10)
            .get(),
      );
      final created = matches.docs.where(
        (doc) =>
            doc.data()['athleteOwnerId'] == athleteUid &&
            doc.data()['startDate'] == startDate,
      );
      expect(
        created,
        isNotEmpty,
        reason: 'assignProgram() should have created a new instance doc.',
      );
    },
    skip: browserSmokeConfig.identityRole != BrowserSmokeIdentityRole.trainer,
  );

  testWidgets(
      'workout publication updates self assignments without program publication',
      (tester) async {
    final waits = BrowserTestWaitContext(
      identity: browserSmokeConfig.identityRole?.name ?? 'unconfigured',
      testFile: _testFile,
      artifactPath: _artifactPath,
      currentRoute: () => _currentRoute(tester),
    );
    await startApp(tester, waits);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(authenticatedAppEntryKey)),
    );
    final uid = container.read(authStateProvider).value!.uid;
    final db = FirebaseFirestore.instance;
    final workouts = WorkoutTemplateRepository(firestore: db);
    final instances = WorkoutInstanceRepository(firestore: db);
    final programs = ProgramRepository(firestore: db);
    final exerciseId = await waits.runStep(
      'create an owned exercise for publication',
      () => ExerciseTemplateRepository(firestore: db).create(
        name: 'Publication exercise',
        description: 'Version propagation',
        instructions: 'Controlled repetitions',
        userId: uid,
      ),
    );
    final templateId = await workouts.create(
      name: 'Publication workout',
      workoutType: WorkoutType.fullBody,
      userId: uid,
    );
    final slot = ExerciseSlot(
      exerciseId: exerciseId,
      exerciseName: 'Publication exercise',
      sortOrder: 0,
      mode: ExerciseMode.reps,
      sets: 3,
      reps: '10',
    );
    await workouts.publishVersion(
      templateId: templateId,
      userId: uid,
      exercises: [slot],
    );
    final programId = await programs.create(
      name: 'Publication program',
      type: ProgramType.personal,
      userId: uid,
    );
    await programs.publishVersion(
      programId: programId,
      userId: uid,
      entries: [
        ProgramScheduleEntry(
          entryId: 'entry',
          workoutTemplateId: templateId,
          workoutTemplateVersion: 1,
          dayOffset: 0,
          sortOrder: 0,
        )
      ],
    );
    final date = DateTime.now()
        .add(const Duration(days: 3))
        .toIso8601String()
        .split('T')
        .first;
    Future<String> assign() => instances.assignWorkout(
          programId: programId,
          athleteId: uid,
          assignedBy: uid,
          workoutTemplateId: templateId,
          workoutTemplateVersion: 1,
          workoutType: WorkoutType.fullBody,
          scheduledDate: date,
        );
    final singleId = await assign();
    final startedId = await assign();
    final copied = await instances.assignProgram(
      programId: programId,
      athleteId: uid,
      assignedBy: uid,
      startDate: date,
    );
    final groupRef =
        db.collection('athleteProgramInstances').doc(copied.programInstanceId);
    final beforeGroup = (await groupRef.get()).data();
    final copiedId = '${copied.assignmentId}-0';
    final drafts = WorkoutCompletionDraftRepository(firestore: db);
    final saved = await drafts.save(WorkoutCompletionDraft(
      instanceId: startedId,
      athleteId: uid,
      rpe: 6,
      durationMinutes: 45,
      revision: 1,
      clientId: 'publication-canary',
      updatedAt: DateTime.now().toUtc(),
      sourceRoute: '/athlete/workouts/$startedId',
      workoutTemplateId: templateId,
      workoutTemplateVersion: 1,
      athleteNotes: 'Keep my original workout',
    ));
    expect(saved.status, WorkoutDraftSaveStatus.saved);
    expect(
        await workouts.publishVersion(
          templateId: templateId,
          userId: uid,
          exercises: [slot.copyWith(sets: 4, reps: '15')],
        ),
        2);
    final refs = [singleId, copiedId]
        .map((id) => db.collection('workoutInstances').doc(id))
        .toList();
    var versions = <int>[];
    await waits.waitForCondition(
      condition:
          'real publication trigger updates standalone and copied assignments',
      isSatisfied: () => versions.length == 2 && versions.every((v) => v == 2),
      pump: () async {
        final snapshots = await Future.wait(refs.map((ref) => ref.get()));
        versions = snapshots
            .map(
                (snapshot) => snapshot.data()!['workoutTemplateVersion'] as int)
            .toList();
        await tester.pump(const Duration(milliseconds: 100));
      },
      timeout: const Duration(seconds: 45),
    );
    expect((await groupRef.get()).data(), beforeGroup);
    expect(
        (await db.collection('programs').doc(programId).get())
            .data()!['currentVersion'],
        1);
    final started = db.collection('workoutInstances').doc(startedId);
    expect((await started.get()).data()!['workoutTemplateVersion'], 1);
    expect(
        (await started.collection('completionDrafts').doc('current').get())
            .data()!['athleteNotes'],
        'Keep my original workout');
    final lateId = await assign();
    var lateVersion = 1;
    await waits.waitForCondition(
      condition:
          'creation trigger refreshes a late assignment from old program entries',
      isSatisfied: () => lateVersion == 2,
      pump: () async {
        lateVersion =
            (await db.collection('workoutInstances').doc(lateId).get())
                .data()!['workoutTemplateVersion'] as int;
        await tester.pump(const Duration(milliseconds: 100));
      },
      timeout: const Duration(seconds: 30),
    );
    final latest = await workouts.getVersion(templateId, 2);
    expect(latest!.exercises.single.sets, 4);
    expect(latest.exercises.single.reps, '15');
    GoRouter.of(tester.element(find.byKey(authenticatedAppEntryKey)))
        .go('/athlete/workouts/$singleId');
    await _waitFor(tester, waits, find.byKey(WorkoutCompletionScreen.titleKey),
        step: 'updated workout opens in the recording screen');
    expect(find.text('Publication exercise'), findsWidgets);
    await binding.takeScreenshot('workout-publication-updated');
    await waits.runStep(
      'complete the updated assignment through authenticated Firestore rules',
      () => instances.completeWorkout(
        instanceId: singleId,
        athleteId: uid,
        rpe: 7,
        durationMinutes: 45,
        expectedWorkoutTemplateId: templateId,
        expectedWorkoutTemplateVersion: 2,
        actuals: [
          ExerciseActual(
            slotId: slot.slotId,
            exerciseId: exerciseId,
            mode: ExerciseMode.reps,
            sets: 4,
            reps: '15',
          )
        ],
      ),
    );
    expect((await refs.first.get()).data()!['status'], 'completed');
  });
}

Future<void> _waitFor(
  WidgetTester tester,
  BrowserTestWaitContext waits,
  Finder finder, {
  required String step,
  Duration timeout = const Duration(seconds: 20),
}) {
  return waits.waitForCondition(
    condition: step,
    isSatisfied: () => finder.evaluate().isNotEmpty,
    pump: () => tester.pump(const Duration(milliseconds: 100)),
    timeout: timeout,
    details: () => 'Visible text: ${_visibleText()}',
  );
}

String _visibleText() {
  return find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .take(20)
      .join(' | ');
}

String _currentRoute(WidgetTester tester) {
  final navigators = find.byType(Navigator);
  if (navigators.evaluate().isEmpty) {
    return '<application not mounted>';
  }
  return GoRouter.of(
    tester.element(navigators.first),
  ).routeInformationProvider.value.uri.toString();
}
