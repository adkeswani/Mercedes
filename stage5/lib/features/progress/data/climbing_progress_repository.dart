import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/programs/data/program_repository.dart';
import 'package:stage5/features/workouts/data/workout_instance_repository.dart';
import 'package:stage5/features/workouts/data/workout_template_repository.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

class ClimbingProgressRepository {
  ClimbingProgressRepository({
    required this.instances,
    required this.templates,
    required this.programs,
  });
  final WorkoutInstanceRepository instances;
  final WorkoutTemplateRepository templates;
  final ProgramRepository programs;

  Future<ClimbingProgressReport> load({
    required String athleteId,
    required ProgressRange range,
  }) async {
    final completions = await instances.getCompletedInRange(
      athleteId: athleteId,
      start: range.previous.start,
      endExclusive: range.endExclusive,
    );
    final versions = <(String, int), WorkoutTemplateVersion>{};
    final titles = <String, String>{};
    final programTitles = <String, String>{};
    final sessions = <ClimbingSession>[];
    final seen = <String>{};
    for (final instance in completions) {
      if (instance.athleteId != athleteId) {
        throw StateError(
          'Progress results must belong to the requested athlete',
        );
      }
      if (!seen.add(instance.id)) continue;
      final key = (instance.workoutTemplateId, instance.workoutTemplateVersion);
      var version = versions[key];
      if (version == null) {
        version = await templates.getVersion(key.$1, key.$2);
        if (version == null) {
          throw StateError(
            'Pinned workout ${key.$1} version ${key.$2} is unavailable',
          );
        }
        versions[key] = version;
      }
      final templateId = instance.workoutTemplateId;
      if (!titles.containsKey(templateId)) {
        final header = await templates.getById(templateId);
        titles[templateId] = header?.name ?? 'Workout title unavailable';
      }
      final programId = progressProgramId(instance);
      if (programId != null && !programTitles.containsKey(programId)) {
        try {
          final program = await programs.getById(programId);
          programTitles[programId] =
              program?.name ?? 'Program details unavailable ($programId)';
        } on FirebaseException catch (error) {
          if (error.code != 'permission-denied') rethrow;
          programTitles[programId] =
              'Program name unavailable (access restricted: $programId)';
        }
      }
      final session = ClimbingSession.fromWorkout(
        instance,
        version,
        workoutName: titles[templateId]!,
        programName: programId == null ? null : programTitles[programId],
      );
      if (session != null) sessions.add(session);
    }
    sessions.sort((a, b) {
      final order = a.date.compareTo(b.date);
      return order == 0 ? a.instanceId.compareTo(b.instanceId) : order;
    });
    return ClimbingProgressReport(range: range, sessions: sessions);
  }
}
