import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/exercises/domain/exercise_template.dart';
import 'package:stage5/features/exercises/presentation/exercise_providers.dart';
import 'package:stage5/features/workouts/presentation/exercise_picker.dart';

void main() {
  testWidgets('exercise picker lists exercises alphabetically by name',
      (tester) async {
    final exercises = [
      _exercise(id: 'ex-pullup', name: 'Pull-up'),
      _exercise(id: 'ex-ankle', name: 'Ankle Circles'),
      _exercise(id: 'ex-squat', name: 'Squat'),
      _exercise(id: 'ex-deadlift', name: 'deadlift'),
    ];

    await tester.pumpWidget(_harness(exercises: exercises));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

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
  });
}

Widget _harness({required List<ExerciseTemplate> exercises}) {
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
              onPressed: () => showExercisePicker(context, ref),
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
