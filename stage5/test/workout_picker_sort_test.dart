import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/enums.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/programs/presentation/workout_picker.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'package:stage5/features/workouts/presentation/workout_providers.dart';

void main() {
  testWidgets('workout picker lists published workouts alphabetically by name',
      (tester) async {
    final workouts = [
      _workout(id: 'w-pull', name: 'Pull Day'),
      _workout(id: 'w-ankle', name: 'Ankle Mobility'),
      _workout(id: 'w-squat', name: 'squat day'),
      _workout(id: 'w-unpublished', name: 'Aardvark Day', published: false),
    ];

    await tester.pumpWidget(_harness(workouts: workouts));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();

    expect(titles, [
      'Ankle Mobility',
      'Pull Day',
      'squat day',
    ]);
  });
}

Widget _harness({required List<WorkoutTemplate> workouts}) {
  return ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => Stream.value(_FakeUser('trainer-1')),
      ),
      workoutTemplatesProvider.overrideWith((ref) => Stream.value(workouts)),
    ],
    child: MaterialApp(
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showWorkoutPicker(context, ref),
              child: const Text('Open picker'),
            ),
          ),
        ),
      ),
    ),
  );
}

WorkoutTemplate _workout({
  required String id,
  required String name,
  bool published = true,
}) {
  final timestamp = DateTime.utc(2026);
  return WorkoutTemplate(
    id: id,
    ownerId: 'trainer-1',
    name: name,
    workoutType: WorkoutType.fullBody,
    currentVersion: published ? 1 : 0,
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
