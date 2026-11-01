import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/workouts/presentation/exercise_picker.dart';

void main() {
  testWidgets(
      'instruction picker keeps alphabetical ordering and pinned selection',
      (tester) async {
    final exercises = [
      _exercise(id: 'ex-pullup', name: 'Pull-up'),
      _exercise(id: 'ex-ankle', name: 'Ankle Circles'),
      _exercise(id: 'ex-squat', name: 'Squat'),
      _exercise(id: 'ex-deadlift', name: 'deadlift'),
    ];

    ExercisePickerResult? selected;
    await tester.pumpWidget(_harness(
      exercises: exercises,
      onSelected: (result) => selected = result,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(find.text('Select instructions'), findsOneWidget);

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();

    expect(titles, [
      'Ankle Circles',
      'deadlift',
      'Pull-up',
      'Squat',
    ]);
    await tester.tap(find.text('Squat'));
    await tester.pumpAndSettle();
    expect(selected?.id, 'ex-squat');
    expect(selected?.version, 1);
    expect(selected?.name, 'Squat');
  });

  testWidgets('empty instruction picker points to the Instruction library',
      (tester) async {
    await tester.pumpWidget(_harness(exercises: []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    expect(
        find.text(
          'No instructions yet. Create an entry in the Instruction library first.',
        ),
        findsOneWidget);
  });
}

Widget _harness({
  required List<ExerciseTemplate> exercises,
  ValueChanged<ExercisePickerResult?>? onSelected,
}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream.value(_FakeUser('trainer-1')),
      ),
      exerciseTemplatesProvider.overrideWith((ref) => Stream.value(exercises)),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final result = await showExercisePicker(context, ref);
                onSelected?.call(result);
              },
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    ),
  );
}

ExerciseTemplate _exercise({required String id, required String name}) {
  final timestamp = DateTime.utc(2026);
  return ExerciseTemplate(
    id: id,
    ownerId: 'trainer-1',
    currentVersion: 1,
    version: ExerciseVersion(
      versionNumber: 1,
      name: name,
      description: 'Description for $name',
      instructions: 'Instructions for $name',
      exerciseType: ExerciseType.strength,
      measurementConfiguration: const ExerciseMeasurementConfiguration(
        primary: ExerciseMeasurementType.repetitions,
      ),
      publishedAt: timestamp,
      publishedBy: 'trainer-1',
    ),
    createdAt: timestamp,
    createdBy: 'trainer-1',
    updatedAt: timestamp,
    updatedBy: 'trainer-1',
  );
}

class _FakeUser extends Fake implements User {
  _FakeUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
}
