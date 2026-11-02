import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/workouts/data/workout_local_day.dart';

void main() {
  test('only expired timestamps on local today request a server repair',
      () async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime(2026, 11, 1, 23, 30);
    final requested = <String>[];
    final localDay = WorkoutLocalDay(repair: (id, offset) async {
      expect(offset, now.timeZoneOffset.inMinutes);
      requested.add(id);
    });
    final reference = firestore.collection('workoutInstances').doc('workout');
    final base = {
      'scheduledDate': calendarDate(now),
      'status': 'scheduled',
      'scheduledAt':
          Timestamp.fromDate(now.subtract(const Duration(hours: 25))),
    };
    for (final overrides in [
      <String, Object?>{},
      {'scheduledDate': '2026-10-31'},
      {'scheduledDate': '2026-11-02'},
      {'status': 'completed'},
      {'scheduledAt': null},
      {'scheduledAt': Timestamp.fromDate(now)},
    ]) {
      await reference.set({...base, ...overrides});
      await localDay.prepare(await reference.get(), now);
    }
    expect(requested, ['workout']);
  });

  test('server repair failures surface to the caller', () async {
    final firestore = FakeFirebaseFirestore();
    final now = DateTime(2026, 11, 1, 23, 30);
    final reference = firestore.collection('workoutInstances').doc('workout');
    await reference.set({
      'scheduledDate': calendarDate(now),
      'status': 'scheduled',
      'scheduledAt':
          Timestamp.fromDate(now.subtract(const Duration(hours: 25))),
    });
    final localDay = WorkoutLocalDay(repair: (_, __) async {
      throw StateError('Server rejected the repair');
    });
    await expectLater(
        localDay.prepare(await reference.get(), now), throwsStateError);
  });
}
