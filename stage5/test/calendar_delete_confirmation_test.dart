import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/data/athlete_program_instance_repository.dart';
import 'package:stage5/features/programs/presentation/athlete_program_instance_providers.dart';
import 'package:stage5/features/programs/presentation/enrollment_providers.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/trainer_calendar_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  late List<String> operations;

  setUp(() {
    operations = [];
  });

  Future<void> openMenu(
    WidgetTester tester, {
    ProgramRelationshipMode mode = ProgramRelationshipMode.subscribed,
  }) async {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final instance = WorkoutInstance(
      id: 'workout',
      programId: 'program',
      athleteId: 'athlete',
      workoutTemplateId: 'template',
      workoutTemplateVersion: 1,
      scheduledDate: date,
      assignedBy: 'trainer',
      assignedAt: now,
      status: WorkoutInstanceStatus.scheduled,
      workoutType: WorkoutType.limit,
      createdAt: now,
      updatedAt: now,
      athleteProgramInstanceId: 'assignment',
      relationshipMode: mode,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_User())),
        myEnrolledProgramsProvider.overrideWith((ref) async => []),
        athleteScheduleProvider
            .overrideWith((ref, range) => Stream.value([instance])),
        workoutTemplateProvider.overrideWith((ref, id) async => null),
        workoutInstanceRepositoryProvider
            .overrideWithValue(_Workouts(operations)),
        athleteProgramInstanceRepositoryProvider
            .overrideWithValue(_Programs(operations)),
      ],
      child: const MaterialApp(
        home: TrainerCalendarScreen(selfService: true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${now.day}'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
  }

  Future<void> confirmDelete(
    WidgetTester tester, {
    bool all = false,
  }) async {
    await tester.tap(find.text('Delete\u2026'));
    await tester.pumpAndSettle();
    if (all) {
      await tester.tap(find.text('All incomplete in this program'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  for (final all in [false, true]) {
    testWidgets('subscribed delete explains stopping updates: all=$all',
        (tester) async {
      await openMenu(tester);
      await confirmDelete(tester, all: all);

      expect(find.text('Stop program updates and delete?'), findsOneWidget);
      expect(
          find.textContaining('Completed workouts are kept'), findsOneWidget);
      expect(find.text('Create an independent copy?'), findsNothing);
      expect(find.text('Create copy'), findsNothing);
      expect(operations, isEmpty);

      await tester.tap(find.text('Continue deleting'));
      await tester.pumpAndSettle();
      expect(operations, [
        'unlink:assignment:athlete:true',
        all ? 'delete-all:assignment:athlete' : 'delete:workout:athlete',
      ]);
    });
  }

  testWidgets('cancelling the update warning does not unlink or delete',
      (tester) async {
    await openMenu(tester);
    await confirmDelete(tester, all: true);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(operations, isEmpty);
    expect(find.text('Stop program updates and delete?'), findsNothing);
  });

  testWidgets('an independent assignment deletes without an unlink warning',
      (tester) async {
    await openMenu(tester, mode: ProgramRelationshipMode.copied);
    await confirmDelete(tester, all: true);

    expect(find.text('Stop program updates and delete?'), findsNothing);
    expect(find.text('Create an independent copy?'), findsNothing);
    expect(operations, ['delete-all:assignment:athlete']);
  });

  testWidgets('rescheduling still uses the independent-copy confirmation',
      (tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Reschedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Create an independent copy?'), findsOneWidget);
    expect(find.text('Create copy'), findsOneWidget);
    expect(find.text('Continue deleting'), findsNothing);
    await tester.tap(find.text('Keep subscribed'));
    await tester.pumpAndSettle();
    expect(operations, isEmpty);
  });
}

class _User extends Fake implements User {
  @override
  String get uid => 'athlete';
}

class _Programs extends Fake implements AthleteProgramInstanceRepository {
  _Programs(this.operations);
  final List<String> operations;

  @override
  Future<void> convertSubscriptionToCopy({
    required String instanceId,
    required String athleteId,
    required bool confirmed,
    String reason = 'structuralCustomization',
  }) async {
    operations.add('unlink:$instanceId:$athleteId:$confirmed');
  }
}

class _Workouts extends Fake implements WorkoutInstanceRepository {
  _Workouts(this.operations);
  final List<String> operations;

  @override
  Future<void> deleteInstance({
    required String instanceId,
    required String ownerId,
  }) async {
    operations.add('delete:$instanceId:$ownerId');
  }

  @override
  Future<int> deleteIncompleteProgramAssignment({
    required String programAssignmentId,
    required String ownerId,
  }) async {
    operations.add('delete-all:$programAssignmentId:$ownerId');
    return 4;
  }
}
