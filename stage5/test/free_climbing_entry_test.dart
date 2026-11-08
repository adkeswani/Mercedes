import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/climbing_completion_input.dart';
import 'package:stage5/features/workouts/domain/workout_block.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/presentation/climbing_completion_card.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

final _block =
    FreeClimbingBlock(blockId: 'old-free', sortOrder: 0, slotId: 'old-slot');

void main() {
  testWidgets(
      '320px entry is compact, one-tap, and preserves row identity on removal',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <Map<String, dynamic>>[];
    Map<String, dynamic>? echoed;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutTemplateRepositoryProvider.overrideWithValue(
            WorkoutTemplateRepository(firestore: FakeFirebaseFirestore()),
          ),
        ],
        child: MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: ListView(
                children: [
                  ClimbingCompletionCard(
                    block: _block,
                    recordingEnabled: true,
                    initialInput: echoed,
                    onChanged: (input) {
                      changes.add(input);
                      setState(() => echoed = input);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add climb'));
    await tester.pump();
    final grade = find.byType(DropdownButtonFormField<String>);
    final attempts = find.widgetWithText(TextFormField, 'Attempts');
    final sent = find.byType(Checkbox);
    final notes = find.widgetWithText(TextFormField, 'Notes');
    final rowId = (changes.last['freeRows'] as List).single['rowId'] as String;
    expect(
      tester.getSize(find.byKey(ValueKey<String>(rowId))).height,
      lessThanOrEqualTo(140),
    );
    expect(
      (tester.getTopLeft(grade).dy - tester.getTopLeft(attempts).dy).abs(),
      lessThan(2),
    );
    expect(
      (tester.getTopLeft(grade).dy - tester.getTopLeft(sent).dy).abs(),
      lessThan(30),
    );
    expect(
      tester.getTopLeft(notes).dy,
      greaterThan(tester.getTopLeft(grade).dy),
    );
    expect(
      find.byType(DropdownButtonFormField<ClimbingGradingSystem>),
      findsNothing,
    );
    expect(tester.widget<TextFormField>(attempts).initialValue, '1');
    expect(tester.widget<Checkbox>(sent).value, isFalse);
    tester.widget<DropdownButtonFormField<String>>(grade).onChanged!('5.13a');
    await tester.pump();
    await tester.enterText(attempts, '3');
    await tester.tap(sent);
    await tester.enterText(notes, 'First climb');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(find.text('Add climb'));
    await tester.pump();
    final rows = changes.last['freeRows'] as List;
    expect(rows, hasLength(2));
    expect(rows.first, containsPair('attempts', '3'));
    expect(rows.first, containsPair('sent', true));
    expect(rows.last, containsPair('grade', '5.13a'));
    expect(rows.last, containsPair('gradingSystem', 'yds'));
    expect(rows.last, containsPair('attempts', '1'));
    expect(rows.last, containsPair('sent', false));
    final remainingId = rows.last['rowId'] as String;
    await tester.tap(find.byTooltip('Remove climb').first);
    await tester.pump();
    expect((changes.last['freeRows'] as List).single['rowId'], remainingId);
    expect(tester.widget<TextFormField>(attempts).initialValue, '1');
    expect(tester.widget<TextFormField>(notes).initialValue, '');
    expect(tester.takeException(), isNull);
  });

  test('legacy draft rows are dropped without losing block notes or RPE', () {
    final input = initialClimbingInput(_block)
      ..['notes'] = 'Keep this'
      ..['rpe'] = 7
      ..['freeRows'] = [
        {
          'rowId': 'legacy',
          'gradingSystem': 'vScale',
          'grade': 'V2',
          'climbs': '4',
          'notes': 'Old count',
        },
        {
          'rowId': 'new',
          'gradingSystem': 'yds',
          'grade': '5.13a',
          'attempts': '2',
          'sent': true,
          'notes': 'New climb',
        },
      ]
      ..['rowIds'] = ['legacy', 'new'];
    validateClimbingInputForBlock(_block, input);
    final stored = climbingInputForStorage(input);
    expect(stored['rowIds'], ['new']);
    expect(stored['notes'], 'Keep this');
    expect(stored['rpe'], 7);
    final actual = climbingActualFromInput(_block, input);
    expect(actual.slotId, 'old-slot');
    expect(actual.freeRows!.single.grade, '5.13a');
    expect(actual.freeRows!.single.attempts, 2);
    expect(actual.freeRows!.single.sent, isTrue);
    expect(actual.freeRows!.single.toMap().containsKey('climbs'), isFalse);
    expect(
      ExerciseActual.fromMap(actual.toMap(), slotId: 'old-slot').toMap(),
      actual.toMap(),
    );
    final invalid = {
      ...input,
      'rowIds': ['new', 'legacy'],
    };
    expect(() => climbingInputForStorage(invalid), throwsFormatException);
  });

  testWidgets('legacy result history loads but hides grade counts',
      (tester) async {
    final actual = ExerciseActual.fromMap(
      {
        'exerciseId': freeClimbingExerciseId,
        'mode': 'reps',
        'climbingType': 'freeClimbing',
        'rowIds': ['legacy'],
        'freeRows': [
          {
            'rowId': 'legacy',
            'gradingSystem': 'vScale',
            'grade': 'V2',
            'climbs': 4,
            'notes': 'Old count',
          },
        ],
        'notes': 'Keep the workout note',
        'rpe': 7,
      },
      slotId: 'old-slot',
    );
    actual.validateForBlock(_block);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ClimbingCompletionCard(
              block: _block,
              recordingEnabled: false,
              actual: actual,
              onChanged: (_) => fail('History cannot write'),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('Old count'), findsNothing);
    expect(find.textContaining('4 × V2'), findsNothing);
    expect(find.text('Climbing note: Keep the workout note'), findsOneWidget);
  });

  test('new per-climb results reject absent and invalid actuals', () {
    final valid = {
      'rowId': 'climb',
      'gradingSystem': 'vScale',
      'grade': 'V4',
      'attempts': 2,
      'sent': false,
      'notes': '',
    };
    for (final invalid in [
      {...valid, 'attempts': 0},
      {...valid, 'attempts': -1},
      {...valid, 'sent': null},
      {...valid, 'attempts': null},
      {...valid, 'climbs': 2},
    ]) {
      expect(() => FreeClimbingResultRow.fromMap(invalid), throwsArgumentError);
    }
  });
}
