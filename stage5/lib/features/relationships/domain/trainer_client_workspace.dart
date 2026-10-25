import 'package:stage5/features/programs/domain/athlete_program_instance.dart';
import 'package:stage5/features/trainer_dashboard/domain/trainer_activity_event.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';

/// Tabs shown within the trainer's single-client workspace hub.
enum ClientWorkspaceTab { all, schedule, programs, workouts, activity }

/// Days of recent and upcoming schedule shown in the Schedule/Workouts tabs.
///
/// Mirrors the bounded-window convention used elsewhere (see
/// `athleteDashboardQueryWindowDays`) so trainers see recent context without
/// an unbounded query.
const int clientWorkspaceScheduleLookbackDays = 7;
const int clientWorkspaceScheduleLookaheadDays = 14;

String clientWorkspaceTabLabel(ClientWorkspaceTab tab) {
  return switch (tab) {
    ClientWorkspaceTab.all => 'All',
    ClientWorkspaceTab.schedule => 'Schedule',
    ClientWorkspaceTab.programs => 'Programs',
    ClientWorkspaceTab.workouts => 'Workouts',
    ClientWorkspaceTab.activity => 'Activity',
  };
}

/// Returns the program instances owned by [athleteId] from a trainer-wide
/// stream that spans every client.
List<AthleteProgramInstance> filterProgramInstancesForAthlete(
  Iterable<AthleteProgramInstance> instances,
  String athleteId,
) {
  return instances
      .where((instance) => instance.athleteOwnerId == athleteId)
      .toList();
}

/// Returns the activity events for [athleteId] from a trainer-wide feed that
/// spans every client.
List<TrainerActivityEvent> filterActivityEventsForAthlete(
  Iterable<TrainerActivityEvent> events,
  String athleteId,
) {
  return events.where((event) => event.athleteId == athleteId).toList();
}

/// Returns workout instances that are not tied to a formal program instance.
///
/// These are one-off assignments (`athleteProgramInstanceId == null`) rather
/// than entries generated from an assigned multi-week program.
List<WorkoutInstance> filterIndependentWorkouts(
  Iterable<WorkoutInstance> instances,
) {
  return instances
      .where((instance) => instance.athleteProgramInstanceId == null)
      .toList();
}
