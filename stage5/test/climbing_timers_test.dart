import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';
import 'package:stage5/features/workouts/presentation/workout_timer_widget.dart';

final _circuit = ClimbingCircuitBlock(
  blockId: 'circuit',
  sortOrder: 0,
  slotId: 'result',
  rows: const [
    ClimbingCircuitRow(
        rowId: 'row',
        gradingSystem: ClimbingGradingSystem.vScale,
        grade: 'V2',
        climbs: 3,
        workSeconds: 3,
        restSeconds: 2),
    ClimbingCircuitRow(
        rowId: 'second',
        gradingSystem: ClimbingGradingSystem.vScale,
        grade: 'V3',
        climbs: 2,
        workSeconds: 5),
  ],
);
final _free = FreeClimbingBlock(
    blockId: 'free',
    sortOrder: 1,
    slotId: 'free-result',
    workSeconds: 7,
    restSeconds: 4);

Finder _timer(String name) => find.byKey(ValueKey<String>('climbing-$name'));
Finder _inside(Finder timer, Finder target) =>
    find.descendant(of: timer, matching: target);

void main() {
  testWidgets('row and overall countdowns are independent execution aids',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <Map<String, dynamic>>[];
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: ListView(children: [
        ClimbingCompletionCard(
            block: _circuit, recordingEnabled: true, onChanged: changes.add),
        ClimbingCompletionCard(
            block: _free, recordingEnabled: true, onChanged: changes.add),
      ]),
    ))));
    final work = _timer('work-timer-circuit-row');
    final rest = _timer('rest-timer-circuit-row');
    final second = _timer('work-timer-circuit-second');
    final free = _timer('work-timer-free');
    expect(find.text(climbingCircuitExerciseId), findsNothing);
    expect(find.byType(WorkoutTimerWidget), findsNWidgets(5));
    await tester.tap(_inside(work, find.byTooltip('Start work timer')));
    await tester.pump(const Duration(seconds: 1));
    expect(_inside(work, find.text('0:02')), findsOneWidget);
    expect(_inside(rest, find.text('0:02')), findsOneWidget);
    expect(_inside(second, find.text('0:05')), findsOneWidget);
    await tester.tap(_inside(work, find.byTooltip('Pause work timer')));
    await tester.pump(const Duration(seconds: 5));
    expect(_inside(work, find.text('0:02')), findsOneWidget);
    await tester.tap(_inside(work, find.byTooltip('Start work timer')));
    await tester.pump(const Duration(seconds: 2));
    expect(_inside(work, find.text('Time!')), findsOneWidget);
    expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((checkbox) => checkbox.value == false),
        isTrue);
    await tester.tap(_inside(work, find.byTooltip('Reset work timer')));
    await tester.pump();
    expect(_inside(work, find.text('0:03')), findsOneWidget);
    await tester.tap(_inside(rest, find.byTooltip('Start rest timer')));
    await tester.pump(const Duration(seconds: 2));
    expect(_inside(rest, find.text('Time!')), findsOneWidget);
    await tester.tap(_inside(free, find.byTooltip('Start work timer')));
    await tester.pump(const Duration(seconds: 3));
    expect(_inside(free, find.text('0:04')), findsOneWidget);
    expect(
        _inside(_timer('rest-timer-free'), find.text('0:04')), findsOneWidget);
    expect(changes, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active countdown survives recycling its offscreen card',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: ListView.builder(
        itemCount: 2,
        itemBuilder: (context, index) => index == 0
            ? ClimbingCompletionCard(
                block: _circuit, recordingEnabled: true, onChanged: (_) {})
            : const SizedBox(
                height: 2000, child: Center(child: Text('bottom'))),
      ),
    ))));
    final work = _timer('work-timer-circuit-row');
    final state = tester.state<WorkoutTimerWidgetState>(work);
    state.start();
    await tester.drag(find.byType(ListView), const Offset(0, -1700));
    await tester.pump(const Duration(seconds: 1));
    expect(state.mounted, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 1700));
    await tester.pump();
    expect(tester.state<WorkoutTimerWidgetState>(work), same(state));
    expect(_inside(work, find.text('0:02')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('completed history displays prescriptions without live clocks',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
      body: ListView(children: [
        ClimbingCompletionCard(
            block: _circuit,
            recordingEnabled: false,
            onChanged: (_) => fail('History must not emit input')),
        ClimbingCompletionCard(
            block: _free,
            recordingEnabled: false,
            onChanged: (_) => fail('History must not emit input')),
      ]),
    ))));
    expect(find.byType(WorkoutTimerWidget), findsNothing);
    expect(find.text('Work: 3s'), findsOneWidget);
    expect(find.text('Rest: 2s'), findsOneWidget);
    expect(find.text('Work: 7s'), findsOneWidget);
    expect(find.text('Rest: 4s'), findsOneWidget);
  });
}
