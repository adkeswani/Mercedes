import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/core/web_workspace/web_workspace_mode.dart';
import 'package:stage5/features/auth/domain/user_profile.dart';
import 'package:stage5/features/auth/presentation/app_entry_providers.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/auth/presentation/web_workspace_shell.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/programs/presentation/athlete_programs_screen.dart';
import 'package:stage5/features/programs/presentation/program_providers.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/athlete_workout_history_screen.dart';
import 'package:stage5/features/workouts/presentation/calendar_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ProgramRepository programRepository;
  late WorkoutTemplateRepository workoutRepository;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    programRepository = ProgramRepository(firestore: firestore);
    workoutRepository = WorkoutTemplateRepository(firestore: firestore);
    final now = DateTime.utc(2026);
    await firestore.collection('programs').doc('program-1').set({
      'name': 'Foundation Strength',
      'ownerId': 'trainer-1',
      'type': 'assignable',
      'status': 'published',
      'currentVersion': 2,
      'createdAt': now,
      'createdBy': 'trainer-1',
      'updatedAt': now,
      'updatedBy': 'trainer-1',
      'deletedAt': null,
    });
    await firestore.collection('workoutTemplates').doc('workout-1').set({
      'name': 'Completed Strength Session',
      'ownerId': 'trainer-1',
      'workoutType': 'push',
      'currentVersion': 1,
      'createdAt': now,
      'createdBy': 'trainer-1',
      'updatedAt': now,
      'updatedBy': 'trainer-1',
      'deletedAt': null,
    });
  });

  Future<void> pumpPrograms(
    WidgetTester tester,
    Stream<List<AthleteProgramInstance>> stream, {
    AsyncValue<int> backfill = const AsyncData(0),
  }) {
    return tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          myAthleteProgramInstancesProvider.overrideWith((ref) => stream),
          myAthleteProgramInstanceBackfillStatusProvider.overrideWithValue(
            backfill,
          ),
          programRepositoryProvider.overrideWithValue(programRepository),
        ],
        child: const MaterialApp(home: AthleteProgramsScreen()),
      ),
    );
  }

  Future<void> pumpHistory(
    WidgetTester tester,
    Stream<List<WorkoutInstance>> stream,
  ) {
    return tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          athleteWorkoutHistoryProvider.overrideWith((ref) => stream),
          workoutTemplateRepositoryProvider.overrideWithValue(
            workoutRepository,
          ),
        ],
        child: const MaterialApp(home: AthleteWorkoutHistoryScreen()),
      ),
    );
  }

  group('AthleteProgramsScreen', () {
    testWidgets('shows loading, empty, error, and populated states', (
      tester,
    ) async {
      await pumpPrograms(tester, const Stream.empty());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pumpPrograms(tester, Stream.value(const []));
      await tester.pumpAndSettle();
      expect(find.textContaining('No program instances yet'), findsOneWidget);

      await pumpPrograms(
        tester,
        Stream.error(StateError('permission-denied')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to load your programs'),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsOneWidget);

      await pumpPrograms(tester, Stream.value([_programInstance()]));
      await tester.pumpAndSettle();
      expect(find.text('Foundation Strength'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('2 workouts'), findsOneWidget);

      await pumpPrograms(
        tester,
        Stream.value([_programInstance()]),
        backfill: const AsyncLoading(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Foundation Strength'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('distinguishes migration failures and missing programs', (
      tester,
    ) async {
      await pumpPrograms(
        tester,
        Stream.value(const []),
        backfill: AsyncError(
          StateError('legacy migration failed'),
          StackTrace.empty,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to import legacy program assignments'),
        findsOneWidget,
      );

      await pumpPrograms(
        tester,
        Stream.value([_programInstance(sourceProgramId: 'missing-program')]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Program details unavailable'), findsOneWidget);
      expect(find.text('Loading program...'), findsNothing);
    });
  });

  group('AthleteWorkoutHistoryScreen', () {
    testWidgets('shows loading, empty, error, and populated states', (
      tester,
    ) async {
      await pumpHistory(tester, const Stream.empty());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pumpHistory(tester, Stream.value(const []));
      await tester.pumpAndSettle();
      expect(find.textContaining('No workout history yet'), findsOneWidget);

      await pumpHistory(tester, Stream.error(StateError('permission-denied')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unable to load workout history'),
        findsOneWidget,
      );
      expect(find.textContaining('permission-denied'), findsOneWidget);

      await pumpHistory(tester, Stream.value([_completedWorkout()]));
      await tester.pumpAndSettle();
      expect(find.text('Completed Strength Session'), findsOneWidget);
      expect(find.textContaining(' · Completed'), findsOneWidget);
      expect(find.textContaining('RPE 8'), findsOneWidget);
    });

    testWidgets('shows a stable fallback for a missing workout template', (
      tester,
    ) async {
      await pumpHistory(
        tester,
        Stream.value([
          _completedWorkout(workoutTemplateId: 'missing-workout'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Workout details unavailable'), findsOneWidget);
      expect(find.text('Loading workout...'), findsNothing);
    });
  });

  group('web workspace account identity', () {
    test('prefers profile display name, username, email, then fallback', () {
      expect(
        webWorkspaceAccountIdentity(profile: _profile()),
        'Athlete Example',
      );
      expect(
        webWorkspaceAccountIdentity(
          profile: _profile(displayName: '', username: 'athlete_name'),
        ),
        'athlete_name',
      );
      expect(
        webWorkspaceAccountIdentity(
          profile: _profile(displayName: '', username: null),
        ),
        'athlete@example.test',
      );
      expect(
        webWorkspaceAccountIdentity(authEmail: 'auth@example.test'),
        'auth@example.test',
      );
      expect(webWorkspaceAccountIdentity(), 'Signed in');
    });

    testWidgets('desktop header identity is accessible and truncates',
        (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => Stream.value(null)),
            userProfileProvider.overrideWith(
              (ref) => Stream.value(
                _profile(
                  displayName:
                      'An exceptionally long athlete display name for web',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: WebWorkspaceShell(
              mode: WebWorkspaceMode.athlete,
              destination: WebWorkspaceDestination.athleteProgress,
              child: SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final identity = tester.widget<Text>(
        find.descendant(
          of: find.byKey(webWorkspaceAccountIdentityKey),
          matching: find.byType(Text),
        ),
      );
      expect(identity.maxLines, 1);
      expect(identity.overflow, TextOverflow.ellipsis);
      expect(
        tester.getSemantics(find.byKey(webWorkspaceAccountIdentityKey)).label,
        contains('Signed in as An exceptionally long athlete'),
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  });

  testWidgets('calendar surfaces provider permission errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          athleteScheduleProvider.overrideWith(
            (ref, range) =>
                Stream.error(StateError('cloud_firestore/permission-denied')),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 900, height: 700, child: CalendarScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('permission-denied'), findsOneWidget);
  });

  testWidgets('calendar resolves workout template names', (tester) async {
    final today = DateTime.now();
    final scheduledDate = '${today.year}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          athleteScheduleProvider.overrideWith(
            (ref, range) => Stream.value([
              _scheduledWorkout(scheduledDate: scheduledDate),
            ]),
          ),
          workoutTemplateRepositoryProvider.overrideWithValue(
            workoutRepository,
          ),
        ],
        child: const MaterialApp(home: CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Completed Strength Session'), findsOneWidget);
    expect(find.text('workout-1'), findsNothing);
  });
}

UserProfile _profile({
  String displayName = 'Athlete Example',
  String? username = 'athlete_example',
}) {
  final now = DateTime.utc(2026);
  return UserProfile(
    uid: 'athlete-1',
    displayName: displayName,
    email: 'athlete@example.test',
    username: username,
    createdAt: now,
    createdBy: 'athlete-1',
    updatedAt: now,
    updatedBy: 'athlete-1',
  );
}

AthleteProgramInstance _programInstance({
  String sourceProgramId = 'program-1',
}) {
  final now = DateTime.utc(2026);
  return AthleteProgramInstance(
    id: 'instance-1',
    athleteOwnerId: 'athlete-1',
    assigningTrainerId: 'trainer-1',
    sourceProgramId: sourceProgramId,
    sourceProgramVersion: 2,
    relationshipMode: ProgramRelationshipMode.subscribed,
    startDate: '2026-01-01',
    expectedEndDate: '2026-02-01',
    workoutCount: 2,
    status: AthleteProgramInstanceStatus.active,
    linkedAt: now,
    createdAt: now,
    createdBy: 'trainer-1',
    updatedAt: now,
    updatedBy: 'trainer-1',
  );
}

WorkoutInstance _completedWorkout({
  String workoutTemplateId = 'workout-1',
}) {
  final now = DateTime.utc(2026);
  return WorkoutInstance(
    id: 'history-1',
    programId: 'program-1',
    athleteId: 'athlete-1',
    workoutTemplateId: workoutTemplateId,
    workoutTemplateVersion: 1,
    scheduledDate: '2025-12-20',
    assignedBy: 'trainer-1',
    assignedAt: now,
    status: WorkoutInstanceStatus.completed,
    workoutType: WorkoutType.push,
    completedAt: now,
    rpe: 8,
    durationMinutes: 45,
    createdAt: now,
    updatedAt: now,
  );
}

WorkoutInstance _scheduledWorkout({required String scheduledDate}) {
  final now = DateTime.now();
  return WorkoutInstance(
    id: 'scheduled-1',
    programId: 'program-1',
    athleteId: 'athlete-1',
    workoutTemplateId: 'workout-1',
    workoutTemplateVersion: 1,
    scheduledDate: scheduledDate,
    assignedBy: 'trainer-1',
    assignedAt: now,
    status: WorkoutInstanceStatus.scheduled,
    workoutType: WorkoutType.push,
    createdAt: now,
    updatedAt: now,
  );
}
