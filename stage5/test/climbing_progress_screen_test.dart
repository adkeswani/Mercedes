import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/climbing_progress_providers.dart';
import 'package:stage5/features/progress/presentation/climbing_progress_screen.dart';
import 'support/climbing_progress_fixtures.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<ClimbingProgressReport> Function(ProgressRange)? load,
  List<ClimbingSession>? sessions,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, __) => const ClimbingProgressScreen()),
      GoRoute(
        path: '/athlete/workouts/:id',
        builder: (_, state) => Scaffold(
          body: Text('Pinned workout ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        progressClockProvider
            .overrideWithValue(() => DateTime(2026, 11, 7, 14)),
        climbingProgressProvider.overrideWith(
          (ref, range) =>
              load?.call(range) ??
              Future.value(
                ClimbingProgressReport(
                  range: range,
                  sessions: sessions ?? [progressSession()],
                ),
              ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byKey(const Key('climbing-progress-scroll')),
        matching: find.byType(Scrollable),
      )
      .first;
  if (finder.evaluate().isEmpty) {
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  await tester.scrollUntilVisible(finder, 300, scrollable: scrollable);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'workout checkboxes update charts, comparison and sources without refetching',
      (tester) async {
    var requests = 0;
    await _pump(
      tester,
      load: (range) async {
        requests++;
        return ClimbingProgressReport(
          range: range,
          sessions: [
            progressSession(id: 'first'),
            progressSession(
                id: 'second', grade: 'V6', date: DateTime(2026, 11, 5)),
            progressSession(id: 'previous', date: DateTime(2026, 10, 5)),
          ],
        );
      },
    );
    await tester.tap(find.text('Choose workouts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Independent workouts'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('progress-include-second')));
    await tester.tap(find.byKey(const Key('progress-include-second')));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 workouts included in this range'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('progress-highest-send')));
    expect(find.text('V4 - preceding period: V4'), findsOneWidget);
    expect(find.byKey(const Key('progress-workout-second')), findsNothing);
    await _reveal(tester, find.byKey(const Key('progress-include-previous')));
    await tester.tap(find.byKey(const Key('progress-include-previous')));
    await tester.pumpAndSettle();
    expect(find.text('0 in preceding 30 days'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('progress-exclude-all')));
    await tester.tap(find.byKey(const Key('progress-exclude-all')));
    await tester.pumpAndSettle();
    expect(find.text('No workouts selected for this range.'), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('progress-include-all')));
    await tester.tap(find.byKey(const Key('progress-include-all')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 workouts included in this range'), findsOneWidget);
    expect(requests, 1);
  });
  testWidgets(
      'program groups collapse, show partial selection and filter locally',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requests = 0;
    await _pump(
      tester,
      load: (range) async {
        requests++;
        return ClimbingProgressReport(
          range: range,
          sessions: [
            progressSession(
              id: 'first',
              programId: 'first',
              programName: 'Climbing plan',
            ),
            progressSession(
              id: 'second',
              programId: 'first',
              programName: 'Climbing plan',
            ),
            progressSession(
              id: 'comparison',
              programId: 'first',
              programName: 'Climbing plan',
              date: DateTime(2026, 10, 5),
            ),
            progressSession(
              id: 'other',
              programId: 'other',
              programName: 'Other plan',
            ),
            progressSession(id: 'independent'),
          ],
        );
      },
    );
    await tester.tap(find.text('Choose workouts'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-include-first')), findsNothing);
    await _reveal(tester, find.text('Climbing plan'));
    await tester.tap(find.text('Climbing plan'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('progress-include-second')));
    await tester.tap(find.byKey(const Key('progress-include-second')));
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('progress-group-check-program:first'));
    expect(tester.widget<Checkbox>(check).value, isNull);
    await _reveal(tester, check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check).value, isTrue);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(check).value, isFalse);
    expect(find.text('2 of 4 workouts included in this range'), findsOneWidget);
    expect(find.text('0 in preceding 30 days'), findsOneWidget);
    await _reveal(tester, find.text('Climbing plan'));
    await tester.tap(find.text('Climbing plan'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-include-first')), findsNothing);
    await _reveal(tester, check);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('4 of 4 workouts included in this range'), findsOneWidget);
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('defaults to 30 days and supports 7, 14, and 12 month presets',
      (tester) async {
    final requests = <ProgressRange>[];
    await _pump(
      tester,
      load: (range) async {
        requests.add(range);
        return ClimbingProgressReport(
          range: range,
          sessions: [progressSession()],
        );
      },
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('progress-range-month')))
          .selected,
      isTrue,
    );
    expect(requests.last.days, 30);
    for (final pair in [('week', 7), ('fortnight', 14), ('year', 365)]) {
      await tester.tap(find.byKey(Key('progress-range-${pair.$1}')));
      await tester.pumpAndSettle();
      expect(requests.last.days, pair.$2);
    }
    await tester.tap(find.byTooltip('Refresh progress'));
    await tester.pumpAndSettle();
    expect(requests.length, 5);
  });
  testWidgets(
      'switching scales changes counts and send trends without mixing grades',
      (tester) async {
    await _pump(tester);
    await _reveal(tester, find.byKey(const Key('progress-grade-vScale-V8')));
    expect(find.byKey(const Key('progress-grade-vScale-V2')), findsOneWidget);
    await _reveal(tester, find.byKey(const Key('progress-highest-send')));
    expect(
      find.text('V4 - preceding period: No recorded sends'),
      findsOneWidget,
    );
    await _reveal(tester, find.byKey(const Key('progress-system-yds')));
    await tester.tap(find.byKey(const Key('progress-system-yds')));
    await tester.pumpAndSettle();
    await _reveal(tester, find.byKey(const Key('progress-grade-yds-5.11a')));
    expect(find.byKey(const Key('progress-grade-vScale-V8')), findsNothing);
    await _reveal(tester, find.byKey(const Key('progress-highest-send')));
    expect(
      find.text('5.11a - preceding period: No recorded sends'),
      findsOneWidget,
    );
  });
  testWidgets(
      'chart point opens source workouts and navigates to immutable detail',
      (tester) async {
    await _pump(tester);
    await _reveal(tester, find.byKey(const Key('progress-sessions-4')));
    await tester.tap(find.byKey(const Key('progress-sessions-4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-source-sheet')), findsOneWidget);
    expect(find.textContaining('2 recorded attempts'), findsWidgets);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('progress-source-sheet')),
        matching: find.byKey(const Key('progress-workout-workout')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pinned workout workout'), findsOneWidget);
  });
  testWidgets('phone layout has no overflow and shows circuit sources',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pump(tester);
    await _reveal(tester, find.textContaining('workout version 1'));
    expect(find.textContaining('1/2 rows'), findsOneWidget);
    expect(
      find.textContaining('V2 x 3, max 2 attempts per climb'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty and unrecorded states are explicit', (tester) async {
    await _pump(tester, sessions: []);
    expect(
      find.text('No completed climbing workouts in this range.'),
      findsOneWidget,
    );
    expect(find.text('Not recorded'), findsWidgets);
  });
  testWidgets('load failure offers working Retry', (tester) async {
    var requests = 0;
    await _pump(
      tester,
      load: (range) {
        requests++;
        if (requests == 1) return Future.error(StateError('Denied'));
        return Future.value(
          ClimbingProgressReport(range: range, sessions: [progressSession()]),
        );
      },
    );
    expect(find.text('Unable to load climbing progress'), findsOneWidget);
    expect(find.textContaining('Denied'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Unable to load climbing progress'), findsNothing);
    expect(requests, 2);
  });
  testWidgets(
      'custom date input applies inclusive range and rejects oversize ranges',
      (tester) async {
    final requests = <ProgressRange>[];
    await _pump(
      tester,
      load: (range) async {
        requests.add(range);
        return ClimbingProgressReport(range: range, sessions: []);
      },
    );
    Future<void> pick(String start, String end) async {
      await tester.tap(find.byKey(const Key('progress-custom-range')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      final inputs = find.byType(TextField);
      await tester.enterText(inputs.at(0), start);
      await tester.enterText(inputs.at(1), end);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await pick('10/25/2026', '11/7/2026');
    expect(requests.last.days, 14);
    expect(find.text('2026-10-25 to 2026-11-07'), findsOneWidget);
    expect(find.text('Custom range selected'), findsOneWidget);
    await pick('1/1/2024', '11/7/2026');
    expect(find.text('Select a range of 1 to 366 days.'), findsOneWidget);
    expect(requests.length, 2);
  });
}
