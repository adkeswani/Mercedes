import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

typedef RepairWorkoutLocalDay = Future<void> Function(
  String instanceId,
  int utcOffsetMinutes,
);

String calendarDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// Repairs expired authorization timestamps, not the workout's calendar date.
///
/// Server propagation used UTC midnight for date-only assignments. Clients
/// cannot extend that authorization themselves, so the callable verifies the
/// owner, scheduled status, and today's date using the server clock.
class WorkoutLocalDay {
  const WorkoutLocalDay({RepairWorkoutLocalDay? repair})
      : _repair = repair ?? _repairOnServer;

  final RepairWorkoutLocalDay _repair;

  Future<void> prepare(
    DocumentSnapshot<Map<String, dynamic>> workout,
    DateTime now,
  ) async {
    final data = workout.data();
    final scheduledAt = data?['scheduledAt'];
    if (data?['scheduledDate'] != calendarDate(now) ||
        data?['status'] != 'scheduled' ||
        scheduledAt is! Timestamp ||
        scheduledAt.toDate().add(const Duration(days: 1)).isAfter(now)) {
      return;
    }
    await _repair(workout.id, now.timeZoneOffset.inMinutes);
  }

  static Future<void> _repairOnServer(
    String instanceId,
    int utcOffsetMinutes,
  ) async {
    await FirebaseFunctions.instance
        .httpsCallable('repairWorkoutLocalDay')
        .call<void>({
      'instanceId': instanceId,
      'utcOffsetMinutes': utcOffsetMinutes,
    });
  }
}
