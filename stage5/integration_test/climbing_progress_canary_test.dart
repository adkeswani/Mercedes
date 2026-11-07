import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:stage5/app.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/progress_line_chart.dart';
import 'package:stage5/features/workouts/presentation/workout_completion_screen.dart';
import 'package:stage5/features/workouts/presentation/workout_instance_providers.dart';
import 'package:stage5/main.dart' as app;

import 'support/browser_test_wait.dart';
import 'support/router_test_utils.dart';

const _testFile = 'integration_test/climbing_progress_canary_test.dart';
const _artifactPath = String.fromEnvironment(
  'BROWSER_TEST_ARTIFACT_PATH',
  defaultValue: '<not provided>',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('climbing progress ranges, interpretation, and pinned history',
      (tester) async {
    final role = browserSmokeConfig.identityRole!;
    final waits = BrowserTestWaitContext(
      identity: role.name,
      testFile: _testFile,
      artifactPath: _artifactPath,
      currentRoute: () => mountedAppRouter(tester)
          .routeInformationProvider
          .value
          .uri
          .toString(),
    );
    Future<void> wait(String condition, bool Function() satisfied) =>
        waits.waitForCondition(
          condition: condition,
          isSatisfied: satisfied,
          pump: () => tester.pump(const Duration(milliseconds: 100)),
          details: () => find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .take(25)
              .join(' | '),
        );
    Future<void> reveal(Finder finder, String condition) async {
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
      await waits.runStep(
        condition,
        () => tester.scrollUntilVisible(finder, 300, scrollable: scrollable),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder, String condition) async {
      await reveal(finder, condition);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Finder summary(String key, String value) => find.descendant(
          of: find.byKey(Key('progress-summary-$key')),
          matching: find.text(value),
        );
    Future<void> preset(String preset, int count) async {
      await tap(
        find.byKey(Key('progress-range-$preset')),
        'select $preset range',
      );
      await wait(
        '$preset range has $count sessions',
        () => summary('sessions', '$count').evaluate().isNotEmpty,
      );
    }

    Future<void> customDates(String start, String end) async {
      await tap(
        find.byKey(const Key('progress-custom-range')),
        'open custom date picker',
      );
      await tester.tap(find.byTooltip('Switch to input'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), start);
      await tester.enterText(find.byType(TextField).at(1), end);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    await waits.runStep(
      'initialize emulators',
      app.initializeMercedesApp,
      timeout: const Duration(seconds: 30),
    );
    await tester.pumpWidget(const ProviderScope(child: MercedesApp()));
    await wait(
      'login control',
      () => find.byKey(browserSmokeLoginButtonKey).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(browserSmokeLoginButtonKey));
    await wait(
      'authenticated application',
      () => find.byKey(authenticatedAppEntryKey).evaluate().isNotEmpty,
    );
    mountedAppRouter(tester).go('/athlete/progress');
    await wait(
      'progress surface',
      () => find
          .byKey(const Key('progress-summary-sessions'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pumpAndSettle();

    if (role == BrowserSmokeIdentityRole.trainer) {
      // A trainer's athlete workspace is their own data, not their client's.
      expect(summary('sessions', '0'), findsOneWidget);
      expect(
        find.text('No completed climbing workouts in this range.'),
        findsOneWidget,
      );
      await preset('fortnight', 0);
      await preset('year', 0);
      expect(
        find.byKey(const Key('progress-workout-browser-progress-1')),
        findsNothing,
      );
      await waits.captureAfterAssertions(
        'trainer own progress screenshot',
        () async => binding.takeScreenshot('trainer-own-progress-empty'),
      );
      return;
    }

    expect(summary('sessions', '2'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const Key('progress-summary-sessions'))),
    );
    final pageNow = DateTime.now();
    final pageDay = DateTime(pageNow.year, pageNow.month, pageNow.day - 1000);
    final pageStart = DateTime(pageDay.year, pageDay.month, pageDay.day);
    final paginated = await waits.runStep(
      'all 105 tied completion timestamps',
      () => container
          .read(workoutInstanceRepositoryProvider)
          .getCompletedInRange(
            athleteId: container.read(authStateProvider).value!.uid,
            start: pageStart,
            endExclusive:
                DateTime(pageStart.year, pageStart.month, pageStart.day + 1),
          ),
    );
    expect(paginated.length, 105);
    expect(paginated.map((instance) => instance.id).toSet().length, 105);
    expect(summary('climbs', '18'), findsOneWidget);
    expect(find.text('1 in preceding 30 days'), findsOneWidget);
    await tap(
      find.text('Choose workouts'),
      'open contributing workout selector',
    );
    await tap(find.text('Browser Athlete Program'), 'expand program workouts');
    await tap(
      find.byKey(const Key('progress-include-browser-progress-10')),
      'exclude a contributing workout',
    );
    expect(summary('sessions', '1'), findsOneWidget);
    expect(summary('climbs', '9'), findsOneWidget);
    final programCheck = find.byKey(
      const Key('progress-group-check-program:browser-athlete-program'),
    );
    expect(tester.widget<Checkbox>(programCheck).value, isNull);
    expect(
      find.byKey(const Key('progress-workout-browser-progress-10')),
      findsNothing,
    );
    await tap(programCheck, 'include partially selected program');
    expect(tester.widget<Checkbox>(programCheck).value, isTrue);
    expect(summary('sessions', '2'), findsOneWidget);
    await tap(find.text('Independent workouts'), 'expand independent workouts');
    await tap(
      find.byKey(const Key('progress-include-browser-progress-35')),
      'exclude a comparison workout',
    );
    expect(find.text('0 in preceding 30 days'), findsOneWidget);
    await tap(
      find.byKey(const Key('progress-exclude-all')),
      'exclude all contributions',
    );
    expect(summary('sessions', '0'), findsOneWidget);
    expect(find.text('No workouts selected for this range.'), findsOneWidget);
    await tap(
      find.byKey(const Key('progress-include-all')),
      'restore all contributions',
    );
    expect(summary('sessions', '2'), findsOneWidget);
    await tap(find.text('Choose workouts'), 'collapse workout selector');
    await preset('week', 1);
    expect(summary('climbs', '9'), findsOneWidget);
    await preset('fortnight', 2);
    await preset('year', 4);
    expect(summary('climbs', '36'), findsOneWidget);
    await tap(find.text('Choose workouts'), 'open cross-program selector');
    await tap(
      find.byKey(
        const Key('progress-group-check-program:browser-athlete-program'),
      ),
      'exclude whole first program',
    );
    expect(summary('sessions', '2'), findsOneWidget);
    await tap(
      find.byKey(
        const Key(
          'progress-group-check-program:browser-progress-second-program',
        ),
      ),
      'exclude second program independently',
    );
    expect(summary('sessions', '1'), findsOneWidget);
    await tap(
      find.byKey(const Key('progress-group-check-independent')),
      'exclude independent group',
    );
    expect(summary('sessions', '0'), findsOneWidget);
    await tap(
      find.byKey(const Key('progress-include-all')),
      'restore all program groups',
    );
    expect(summary('sessions', '4'), findsOneWidget);
    await tap(find.text('Choose workouts'), 'collapse cross-program selector');

    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day - 10);
    final to = DateTime(today.year, today.month, today.day - 1);
    String input(DateTime day) => '${day.month}/${day.day}/${day.year}';
    await customDates(input(from), input(to));
    await wait(
      'inclusive custom dates have two sessions',
      () => summary('sessions', '2').evaluate().isNotEmpty,
    );
    expect(find.text('Custom range selected'), findsOneWidget);
    await customDates('1/1/2000', '1/2/2000');
    await wait(
      'custom empty history',
      () => summary('sessions', '0').evaluate().isNotEmpty,
    );
    expect(
      find.text('No completed climbing workouts in this range.'),
      findsOneWidget,
    );
    await preset('month', 2);
    await tap(find.byTooltip('Refresh progress'), 'refresh progress');
    await wait(
      'refreshed sessions',
      () => summary('sessions', '2').evaluate().isNotEmpty,
    );

    await reveal(
      find.byKey(const Key('progress-grade-vScale-V8')),
      'recorded V8 counts',
    );
    expect(find.text('V8 · 8'), findsOneWidget);
    final gradePainter = tester
        .widget<CustomPaint>(
          find.byKey(const Key('progress-grade-volume-lines')),
        )
        .painter! as ProgressLineChartPainter;
    expect(
      gradePainter.series.last.values
          .where((value) => value != null && value > 0)
          .toList(),
      [4, 4],
    );
    expect(find.textContaining('Counts combine'), findsNothing);
    expect(find.textContaining('Grades are ordered'), findsNothing);
    await reveal(
      find.byKey(const Key('progress-highest-send')),
      'highest confirmed send',
    );
    expect(find.text('V4 - preceding period: V4'), findsOneWidget);
    expect(find.textContaining('V9 - preceding period'), findsNothing);
    await tap(find.byKey(const Key('progress-system-yds')), 'select YDS');
    await reveal(
      find.byKey(const Key('progress-grade-yds-5.11a')),
      'YDS grade distribution',
    );
    expect(find.byKey(const Key('progress-grade-vScale-V8')), findsNothing);
    await reveal(
      find.byKey(const Key('progress-highest-send')),
      'YDS send trend',
    );
    expect(find.text('5.11a - preceding period: 5.11a'), findsOneWidget);
    await tap(
      find.byKey(const Key('progress-system-vScale')),
      'restore V-scale',
    );

    final monthWeeks = ClimbingProgressReport(
      range: ProgressPreset.month.range(DateTime.now()),
      sessions: [],
    ).weeklyBuckets;
    final recentWeek = monthWeeks.indexWhere(
      (week) => week.range.contains(
        DateTime(pageNow.year, pageNow.month, pageNow.day - 1, 12),
      ),
    );
    await tap(
      find.byKey(Key('progress-volume-$recentWeek')),
      'chart point drill-down',
    );
    await wait(
      'source workout sheet',
      () =>
          find.byKey(const Key('progress-source-sheet')).evaluate().isNotEmpty,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('progress-source-sheet')),
        matching: find.textContaining('2 recorded attempts'),
      ),
      findsOneWidget,
    );
    final source = find.descendant(
      of: find.byKey(const Key('progress-source-sheet')),
      matching: find.byKey(const Key('progress-workout-browser-progress-1')),
    );
    await tester.tap(source);
    await wait(
      'immutable workout detail',
      () => find.text('Workout Details').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<WorkoutCompletionScreen>(
            find.byType(WorkoutCompletionScreen),
          )
          .instanceId,
      'browser-progress-1',
    );
    expect(find.textContaining('Grade V4'), findsOneWidget);
    expect(find.textContaining('Grade V9'), findsNothing);
    expect(find.text('Mark as Completed'), findsNothing);
    expect(find.textContaining('permission-denied'), findsNothing);
    mountedAppRouter(tester).go('/athlete/progress');
    await wait(
      'return to progress',
      () => summary('sessions', '2').evaluate().isNotEmpty,
    );
    await reveal(
      find.textContaining('Climbing Circuit - workout version 1'),
      'circuit trend',
    );
    expect(find.textContaining('1/2 rows'), findsNWidgets(3));
    expect(
      find.textContaining('V2 x 3, max 2 attempts per climb'),
      findsOneWidget,
    );
    expect(find.textContaining('Preceding period'), findsWidgets);

    await waits.captureAfterAssertions('progress screenshots', () async {
      await tap(
        find.byKey(const Key('progress-range-month')),
        'screenshot monthly range',
      );
      await wait(
        'monthly screenshot loaded',
        () => summary('sessions', '2').evaluate().isNotEmpty,
      );
      tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('climbing-progress-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await binding.takeScreenshot('athlete-climbing-progress');
      await tap(find.text('Choose workouts'), 'screenshot workout selection');
      await tap(
        find.text('Browser Athlete Program'),
        'screenshot expanded program',
      );
      await tap(
        find.byKey(const Key('progress-include-browser-progress-10')),
        'screenshot selected contributions',
      );
      expect(summary('sessions', '1'), findsOneWidget);
      await reveal(
        find.text('Browser Athlete Program'),
        'group selector screenshot',
      );
      await binding.takeScreenshot('athlete-climbing-progress-program-groups');
      await tap(
        find.text('Choose workouts'),
        'collapse selected contributions',
      );
      await binding.takeScreenshot('athlete-climbing-progress-selected');
      await tap(
        find.text('Choose workouts'),
        'restore screenshot contributions',
      );
      await tap(
        find.byKey(const Key('progress-include-all')),
        'include all for trend screenshots',
      );
      await tap(
        find.text('Choose workouts'),
        'collapse restored contributions',
      );
      await reveal(
        find.text('Highest grade sent each week'),
        'send chart screenshot',
      );
      await binding.takeScreenshot('athlete-climbing-progress-performance');
      await reveal(
        find.text('Recorded climbs by grade each week'),
        'grade volume line screenshot',
      );
      await binding.takeScreenshot('athlete-climbing-progress-grade-volume');
      await reveal(
        find.textContaining('Climbing Circuit - workout version 1'),
        'circuit screenshot',
      );
      await binding.takeScreenshot('athlete-climbing-progress-circuits');
    });
  });
}
