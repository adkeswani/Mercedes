import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/features/auth/presentation/auth_providers.dart';
import 'package:stage5/features/progress/data/climbing_progress_repository.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/progress/presentation/climbing_progress_providers.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';
import 'support/climbing_progress_fixtures.dart';

Future<void> seedProgressCompletion(
    FakeFirebaseFirestore db, String id, DateTime date,
    {String athlete = 'athlete',
    int version = 1,
    String status = 'completed',
    bool subcollection = false}) async {
  final instance =
      progressInstance(id: id, athlete: athlete, date: date, version: version);
  final ref = db.collection('workoutInstances').doc(id);
  await ref.set({
    'programId': 'program',
    'athleteId': athlete,
    'workoutTemplateId': 'template',
    'workoutTemplateVersion': version,
    'scheduledDate': '2020-01-01',
    'assignedBy': 'trainer',
    'assignedAt': Timestamp.fromDate(date),
    'status': status,
    'workoutType': 'limit',
    'completedAt': Timestamp.fromDate(date),
    'rpe': 7,
    'durationMinutes': 45,
    'createdAt': Timestamp.fromDate(date),
    'updatedAt': Timestamp.fromDate(date),
    if (subcollection) ...{
      'actualsStorageFormat': 'slotResultsSubcollection',
      'actualSlotIds': instance.actualsBySlot.keys.toList(),
    } else
      'actualsBySlot': {
        for (final actual in instance.actuals) actual.slotId: actual.toMap(),
      },
  });
  if (subcollection) {
    for (final actual in instance.actuals) {
      await ref
          .collection('slotResults')
          .doc(actual.slotId)
          .set(actual.toMap());
    }
  }
}

class _Templates extends WorkoutTemplateRepository {
  _Templates(FakeFirebaseFirestore db) : super(firestore: db);
  final calls = <int>[];
  bool missing = false;
  @override
  Future<WorkoutTemplateVersion?> getVersion(
      String templateId, int versionNumber) async {
    calls.add(versionNumber);
    return missing
        ? null
        : progressVersion(
            version: versionNumber, grade: versionNumber == 1 ? 'V4' : 'V9');
  }
}

void main() {
  test('pages all completions with exact bounds and athlete scope', () async {
    final db = FakeFirebaseFirestore();
    final date = DateTime(2026, 11, 6, 12);
    for (var i = 0; i < 105; i++) {
      await seedProgressCompletion(db, 'tie-${i.toString().padLeft(3, '0')}',
          date.add(Duration(seconds: i)));
    }
    await seedProgressCompletion(db, 'other', date, athlete: 'other');
    await seedProgressCompletion(db, 'scheduled', date, status: 'scheduled');
    await seedProgressCompletion(db, 'before', DateTime(2026, 11, 5, 23, 59));
    await seedProgressCompletion(db, 'after', DateTime(2026, 11, 7));
    final result = await WorkoutInstanceRepository(firestore: db)
        .getCompletedInRange(
            athleteId: 'athlete',
            start: DateTime(2026, 11, 6),
            endExclusive: DateTime(2026, 11, 7));
    expect(result.length, 105);
    expect(result.map((i) => i.id).toSet().length, 105);
    expect(result.every((i) => i.id.startsWith('tie-')), isTrue);
    expect(result.first.id, 'tie-104');
    expect(result.last.id, 'tie-000');
  });
  test('hydrates slot children and uses pinned versions once per load',
      () async {
    final db = FakeFirebaseFirestore();
    final templates = _Templates(db);
    await seedProgressCompletion(db, 'old', DateTime(2026, 10, 15),
        subcollection: true);
    await seedProgressCompletion(db, 'recent', DateTime(2026, 11, 6),
        subcollection: true);
    await seedProgressCompletion(db, 'new-version', DateTime(2026, 11, 7),
        version: 2);
    final repository = ClimbingProgressRepository(
        instances: WorkoutInstanceRepository(firestore: db),
        templates: templates);
    final report = await repository.load(
        athleteId: 'athlete',
        range: ProgressPreset.fortnight.range(DateTime(2026, 11, 7)));
    expect(report.current.sessionCount, 2);
    expect(report.previous.sessionCount, 1);
    expect(report.current.recordedClimbs, 18);
    expect(report.current.highestSend(ClimbingGradingSystem.vScale), 'V9');
    expect(templates.calls.toSet(), {1, 2});
    expect(templates.calls.length, 2);
  });
  test('missing pinned versions and missing declared results fail visibly',
      () async {
    final db = FakeFirebaseFirestore();
    final templates = _Templates(db)..missing = true;
    await seedProgressCompletion(db, 'recent', DateTime(2026, 11, 6),
        subcollection: true);
    final repository = ClimbingProgressRepository(
        instances: WorkoutInstanceRepository(firestore: db),
        templates: templates);
    final range = ProgressPreset.month.range(DateTime(2026, 11, 7));
    await expectLater(
        repository.load(athleteId: 'athlete', range: range), throwsStateError);
    templates.missing = false;
    await db
        .collection('workoutInstances')
        .doc('recent')
        .collection('slotResults')
        .doc('free')
        .delete();
    await expectLater(
        repository.load(athleteId: 'athlete', range: range), throwsStateError);
  });
  test(
      'provider derives athlete scope from auth and reloads after identity changes',
      () async {
    final db = FakeFirebaseFirestore();
    await seedProgressCompletion(db, 'athlete-workout', DateTime(2026, 11, 6));
    await seedProgressCompletion(db, 'other-workout', DateTime(2026, 11, 6),
        athlete: 'other');
    final auth = StreamController<User?>();
    final container = ProviderContainer(overrides: [
      authStateProvider.overrideWith((ref) => auth.stream),
      climbingProgressRepositoryProvider.overrideWithValue(
          ClimbingProgressRepository(
              instances: WorkoutInstanceRepository(firestore: db),
              templates: _Templates(db))),
    ]);
    addTearDown(() async {
      container.dispose();
      await auth.close();
    });
    final provider = climbingProgressProvider(
        ProgressPreset.month.range(DateTime(2026, 11, 7)));
    final subscription = container.listen(provider, (_, __) {});
    addTearDown(subscription.close);
    auth.add(_User('athlete'));
    await container.read(authStateProvider.future);
    final first = await container.read(provider.future);
    expect(first.current.sessions.single.instanceId, 'athlete-workout');
    auth.add(_User('other'));
    await Future<void>.delayed(Duration.zero);
    final second = await container.read(provider.future);
    expect(second.current.sessions.single.instanceId, 'other-workout');
    auth.add(null);
    await Future<void>.delayed(Duration.zero);
    await expectLater(container.read(provider.future), throwsStateError);
  });
}

class _User extends Fake implements User {
  _User(this.uid);
  @override
  final String uid;
}
