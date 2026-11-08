import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/presentation/enrollment_providers.dart';
import 'package:stage5/features/workouts/data/workout_local_day.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/calendar_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  final today = DateTime.now();
  final tomorrow = DateTime(today.year, today.month, today.day + 1);
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  WorkoutInstance workout(String id, DateTime date,
      [WorkoutInstanceStatus status = WorkoutInstanceStatus.scheduled]) {
    return WorkoutInstance(
      id: id,
      programId: 'program',
      athleteId: 'athlete',
      workoutTemplateId: id,
      workoutTemplateVersion: 1,
      scheduledDate: calendarDate(date),
      assignedBy: 'trainer',
      assignedAt: today,
      status: status,
      workoutType: WorkoutType.limit,
      createdAt: today,
      updatedAt: today,
    );
  }

  Future<void> mount(
    WidgetTester tester, {
    Stream<List<WorkoutInstance>>? schedule,
    List<DateRange>? ranges,
  }) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const CalendarScreen()),
      GoRoute(
        path: '/athlete/workouts/:id',
        builder: (_, state) => Scaffold(
          body: Text('Workout ${state.pathParameters['id']}'),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => Stream.value(_User())),
        myEnrolledProgramsProvider.overrideWith((ref) async => []),
        athleteScheduleProvider.overrideWith((ref, range) {
          ranges?.add(range);
          return schedule ??
              Stream.value([
                workout('today', today),
                workout('tomorrow', tomorrow),
                workout('completed', today, WorkoutInstanceStatus.completed),
                workout('past', yesterday),
              ]);
        }),
        workoutTemplateProvider.overrideWith((ref, id) async => WorkoutTemplate(
              id: id,
              ownerId: 'trainer',
              name: '$id workout',
              workoutType: WorkoutType.limit,
              currentVersion: 1,
              createdAt: today,
              createdBy: 'trainer',
              updatedAt: today,
              updatedBy: 'trainer',
            )),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openDay(WidgetTester tester, DateTime date) async {
    await tester
        .tap(find.byKey(ValueKey('calendar-day-${calendarDate(date)}')));
    await tester.pumpAndSettle();
  }

  testWidgets('month requests the whole month and navigates across years',
      (tester) async {
    final ranges = <DateRange>[];
    await mount(tester, ranges: ranges);
    expect(
        ranges.last.startDate, calendarDate(DateTime(today.year, today.month)));
    expect(ranges.last.endDate,
        calendarDate(DateTime(today.year, today.month + 1, 0)));
    expect(find.text('today workout'), findsNothing);
    for (var month = today.month; month <= 12; month++) {
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    }
    expect(ranges.last.startDate, '${today.year + 1}-01-01');
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(find.text('December ${today.year}'), findsOneWidget);
  });

  testWidgets('selected day lists its named workouts and management actions',
      (tester) async {
    await mount(tester);
    await openDay(tester, today);
    expect(find.text('today workout'), findsOneWidget);
    expect(find.text('completed workout'), findsOneWidget);
    expect(find.text('tomorrow workout'), findsNothing);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    expect(find.text('Schedule workout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final tapButton in [false, true]) {
    testWidgets('workout ${tapButton ? 'Begin button' : 'row'} opens detail',
        (tester) async {
      await mount(tester);
      await openDay(tester, today);
      await tester.tap(find.text(tapButton ? 'Begin' : 'today workout'));
      await tester.pumpAndSettle();
      expect(find.text('Workout today'), findsOneWidget);
    });
  }

  testWidgets('completed workout opens history without a Begin button',
      (tester) async {
    await mount(tester);
    await openDay(tester, today);
    await tester.tap(find.text('completed workout'));
    await tester.pumpAndSettle();
    expect(find.text('Workout completed'), findsOneWidget);
  });

  testWidgets('past scheduled workouts can be completed but not deleted',
      (tester) async {
    await mount(tester);
    if (yesterday.month != today.month) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    }
    await openDay(tester, yesterday);
    expect(find.text('past workout'), findsOneWidget);
    expect(find.text('Begin'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('schedule updates remove workouts from reopened day',
      (tester) async {
    final controller = StreamController<List<WorkoutInstance>>();
    addTearDown(controller.close);
    controller.add([workout('today', today)]);
    await mount(tester, schedule: controller.stream);
    await openDay(tester, today);
    expect(find.text('today workout'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    controller.add([]);
    await tester.pumpAndSettle();
    await openDay(tester, today);
    expect(find.text('No workouts on this day'), findsOneWidget);
    expect(find.text('today workout'), findsNothing);
  });

  testWidgets('month and day actions fit a narrow phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    await openDay(tester, today);
    expect(find.text('today workout'), findsOneWidget);
    expect(find.text('Begin').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _User extends Fake implements User {
  @override
  String get uid => 'athlete';
}
