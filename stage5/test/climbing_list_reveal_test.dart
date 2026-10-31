import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/enums.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';

import '../integration_test/support/list_test_utils.dart';

ClimbingCompletionCard _card({
  ValueChanged<Map<String, dynamic>>? onChanged,
}) =>
    ClimbingCompletionCard(
      block: ClimbingCircuitBlock(
        blockId: 'circuit',
        sortOrder: 0,
        exercise: ExerciseSlot(
          slotId: 'slot',
          exerciseId: 'exercise',
          sortOrder: 0,
          mode: ExerciseMode.reps,
        ),
        rows: const [
          ClimbingCircuitRow(
            rowId: 'row-boulder',
            gradingSystem: ClimbingGradingSystem.vScale,
            grade: 'V2',
            climbs: 3,
          ),
        ],
      ),
      recordingEnabled: true,
      onChanged: onChanged ?? (_) {},
    );

void main() {
  testWidgets('prescribed rows use the stable String key used by the canary',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: _card())),
      ),
    ));
    expect(find.text('3 × V2'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('row-boulder')), findsOneWidget);
  });

  testWidgets('reveals an unbuilt prescribed row and a recycled earlier card',
      (tester) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sidebar = ScrollController();
    final workout = ScrollController();
    addTearDown(sidebar.dispose);
    addTearDown(workout.dispose);
    Map<String, dynamic>? changed;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Row(children: [
            SizedBox(
              width: 120,
              child: ListView.builder(
                controller: sidebar,
                itemCount: 30,
                itemBuilder: (_, index) =>
                    SizedBox(height: 100, child: Text('Sidebar $index')),
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('workout-list'),
                controller: workout,
                cacheExtent: 0,
                itemCount: 15,
                itemBuilder: (_, index) => switch (index) {
                  6 => _card(onChanged: (input) => changed = input),
                  14 =>
                    const SizedBox(height: 200, child: Text('After workout')),
                  _ => const SizedBox(height: 200),
                },
              ),
            ),
          ]),
        ),
      ),
    ));
    final scrollable = find
        .descendant(
          of: find.byKey(const Key('workout-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    final checkbox = find.descendant(
      of: find.byKey(const ValueKey<String>('row-boulder')),
      matching: find.byType(Checkbox),
    );
    expect(checkbox, findsNothing);
    await revealListTarget(tester, checkbox, scrollable: scrollable);
    expect(checkbox.hitTestable(), findsOneWidget);
    await tester.tap(checkbox);
    await tester.pump();
    expect(changed!['circuitRows'][0]['completed'], isTrue);
    expect(workout.offset, greaterThan(0));
    expect(sidebar.offset, 0);

    await revealListTarget(tester, find.text('After workout'),
        scrollable: scrollable);
    expect(checkbox, findsNothing);
    await revealListTarget(tester, checkbox, scrollable: scrollable);
    expect(checkbox.hitTestable(), findsOneWidget);
    expect(sidebar.offset, 0);
  });
}
