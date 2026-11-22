import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

Future<WorkoutTimerWidgetState> _pumpTimer(
  WidgetTester tester, {
  required DateTime Function() now,
  int? targetSeconds,
  int? initialTargetSeconds,
  ValueChanged<int?>? onTargetChanged,
  ValueChanged<int>? onElapsedChanged,
  VoidCallback? onCompleted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkoutTimerWidget(
          label: 'Work',
          targetSeconds: targetSeconds,
          initialTargetSeconds: initialTargetSeconds,
          onTargetChanged: onTargetChanged,
          onElapsedChanged: onElapsedChanged,
          onCompleted: onCompleted,
        ),
      ),
    ),
  );
  final state =
      tester.state<WorkoutTimerWidgetState>(find.byType(WorkoutTimerWidget));
  state.now = now;
  return state;
}

void main() {
  testWidgets('timer controls fit narrow exercise cards', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: WorkoutTimerWidget(label: 'Time cap', targetSeconds: 120),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Change time cap timer duration'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
  });

  testWidgets('caller can retain an override when a timer is recreated',
      (tester) async {
    final targets = <int?>[];
    final now = DateTime.utc(2026, 11, 22);
    await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 30,
      onTargetChanged: targets.add,
    );
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '60');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(targets, [60]);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 30,
      initialTargetSeconds: targets.last,
      onTargetChanged: targets.add,
    );
    expect(find.text('1:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pumpAndSettle();
    expect(targets, [60, 30]);
    expect(find.text('0:30'), findsOneWidget);
  });

  testWidgets('changing a running countdown resets it without changing default',
      (tester) async {
    var now = DateTime.utc(2026, 11, 22);
    final elapsed = <int>[];
    var completions = 0;
    final state = await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 10,
      onElapsedChanged: elapsed.add,
      onCompleted: () => completions++,
    );
    state.start();
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    expect(find.text('Trainer default: 10 seconds'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '5');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('0:05'), findsOneWidget);
    expect(elapsed, [3, 0]);
    expect(
      tester
          .widget<WorkoutTimerWidget>(find.byType(WorkoutTimerWidget))
          .targetSeconds,
      10,
    );
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:05'), findsOneWidget);
    state.start();
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Time!'), findsOneWidget);
    expect(completions, 1);
    state.reset();
    await tester.pump();
    expect(find.text('0:05'), findsOneWidget);
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pumpAndSettle();
    expect(find.text('0:10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid or cancelled changes preserve the existing countdown',
      (tester) async {
    final state = await _pumpTimer(
      tester,
      now: () => DateTime.utc(2026, 11, 22),
      targetSeconds: 10,
    );
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    for (final invalid in ['0', '-1', '1.5', '', '2147483648']) {
      await tester.enterText(find.byType(TextFormField), invalid);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
          find.textContaining('Enter a positive whole number'), findsOneWidget);
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('0:10'), findsOneWidget);
    state.start();
    state.pause();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stopwatch can become a countdown and restore its default',
      (tester) async {
    await _pumpTimer(tester, now: () => DateTime.utc(2026, 11, 22));
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    expect(find.text('Default: stopwatch'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '75');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('1:15'), findsOneWidget);
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pumpAndSettle();
    expect(find.text('0:00'), findsOneWidget);
  });

  testWidgets('parent rebuild preserves override unless prescription changes',
      (tester) async {
    final now = DateTime.utc(2026, 11, 22);
    await _pumpTimer(tester, now: () => now, targetSeconds: 10);
    await tester.tap(find.byTooltip('Change work timer duration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '20');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    await _pumpTimer(tester, now: () => now, targetSeconds: 10);
    expect(find.text('0:20'), findsOneWidget);
    await _pumpTimer(tester, now: () => now, targetSeconds: 15);
    expect(find.text('0:15'), findsOneWidget);
  });

  testWidgets(
      'one delayed callback catches up a stopwatch without replaying ticks',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final elapsed = <int>[];
    final state = await _pumpTimer(
      tester,
      now: () => now,
      onElapsedChanged: elapsed.add,
    );
    state.start();
    now = now.add(const Duration(seconds: 125));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2:05'), findsOneWidget);
    expect(elapsed, [125]);
    await tester.pump(const Duration(seconds: 1));
    expect(elapsed, [125]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'suspended countdown catches up on resume and completes only once',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final elapsed = <int>[];
    var completions = 0;
    final state = await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 10,
      onElapsedChanged: elapsed.add,
      onCompleted: () => completions++,
    );
    state.start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Time!'), findsOneWidget);
    expect(elapsed, [10]);
    expect(completions, 1);
    state.start();
    now = now.add(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(elapsed, [10]);
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resuming a stopwatch refreshes immediately without a tick',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final state = await _pumpTimer(tester, now: () => now);
    state.start();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 3, seconds: 12));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('3:12'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pause captures partial seconds and excludes paused time',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final elapsed = <int>[];
    final state = await _pumpTimer(
      tester,
      now: () => now,
      onElapsedChanged: elapsed.add,
    );
    state.start();
    now = now.add(const Duration(milliseconds: 700));
    state.pause();
    now = now.add(const Duration(hours: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('0:00'), findsOneWidget);
    expect(elapsed, isEmpty);
    state.start();
    now = now.add(const Duration(milliseconds: 400));
    state.pause();
    await tester.pump();
    expect(find.text('0:01'), findsOneWidget);
    expect(elapsed, [1]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pausing after missed expiry completes instead of losing time',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    var completions = 0;
    final state = await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 3,
      onCompleted: () => completions++,
    );
    state.start();
    now = now.add(const Duration(seconds: 20));
    state.pause();
    await tester.pump();
    expect(find.text('Time!'), findsOneWidget);
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reset clears timestamps and allows a new countdown completion',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final elapsed = <int>[];
    var completions = 0;
    final state = await _pumpTimer(
      tester,
      now: () => now,
      targetSeconds: 2,
      onElapsedChanged: elapsed.add,
      onCompleted: () => completions++,
    );
    state.start();
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    state.reset();
    now = now.add(const Duration(hours: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:02'), findsOneWidget);
    expect(elapsed, [2, 0]);
    state.start();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:01'), findsOneWidget);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(completions, 2);
    expect(elapsed, [2, 0, 1, 2]);
    state.reset();
    state.start();
    now = now.add(const Duration(milliseconds: 500));
    state.reset();
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(completions, 2);
    expect(find.text('0:02'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clock moving backwards cannot decrease elapsed seconds',
      (tester) async {
    final start = DateTime.utc(2026, 11, 7);
    var now = start;
    final elapsed = <int>[];
    final state = await _pumpTimer(
      tester,
      now: () => now,
      onElapsedChanged: elapsed.add,
    );
    state.start();
    now = start.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    now = start.subtract(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0:05'), findsOneWidget);
    expect(elapsed, [5]);
    now = start.add(const Duration(seconds: 8));
    await tester.pump(const Duration(seconds: 1));
    expect(elapsed, [5, 8]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing an active timer removes ticker and lifecycle observer',
      (tester) async {
    var now = DateTime.utc(2026, 11, 7);
    final elapsed = <int>[];
    final state = await _pumpTimer(
      tester,
      now: () => now,
      onElapsedChanged: elapsed.add,
    );
    state.start();
    await tester.pumpWidget(const SizedBox.shrink());
    now = now.add(const Duration(seconds: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(elapsed, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
