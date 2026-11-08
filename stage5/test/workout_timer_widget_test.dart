import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

Future<WorkoutTimerWidgetState> _pumpTimer(
  WidgetTester tester, {
  required DateTime Function() now,
  int? targetSeconds,
  ValueChanged<int>? onElapsedChanged,
  VoidCallback? onCompleted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkoutTimerWidget(
          label: 'Work',
          targetSeconds: targetSeconds,
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
