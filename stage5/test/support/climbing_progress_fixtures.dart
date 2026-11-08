import 'package:stage5/core/enums.dart';
import 'package:stage5/features/progress/domain/climbing_progress.dart';
import 'package:stage5/features/workouts/domain/climbing.dart';
import 'package:stage5/features/workouts/domain/workout_instance.dart';
import 'package:stage5/features/workouts/domain/workout_template.dart';

WorkoutTemplateVersion progressVersion(
        {int version = 1, String grade = 'V4'}) =>
    WorkoutTemplateVersion(
      versionNumber: version,
      publishedAt: DateTime(2026),
      blocks: [
        ClimbingRouteBlock(
          blockId: 'route',
          sortOrder: 0,
          route: ExerciseSlot(
              slotId: 'route',
              exerciseId: 'route-exercise',
              sortOrder: 0,
              mode: ExerciseMode.reps,
              exerciseName: 'Boulder'),
          grade: grade,
          gradingSystem: ClimbingGradingSystem.vScale,
        ),
        ClimbingRouteBlock(
          blockId: 'rope',
          sortOrder: 1,
          route: ExerciseSlot(
              slotId: 'rope',
              exerciseId: 'rope-exercise',
              sortOrder: 0,
              mode: ExerciseMode.reps,
              exerciseName: 'Rope route'),
          grade: '5.11a',
          gradingSystem: ClimbingGradingSystem.yds,
        ),
        ClimbingCircuitBlock(
          blockId: 'circuit',
          sortOrder: 2,
          slotId: 'circuit',
          rows: const [
            ClimbingCircuitRow(
                rowId: 'boulders',
                gradingSystem: ClimbingGradingSystem.vScale,
                grade: 'V2',
                climbs: 3,
                maxAttemptsPerClimb: 2),
            ClimbingCircuitRow(
                rowId: 'ropes',
                gradingSystem: ClimbingGradingSystem.yds,
                grade: '5.10a',
                climbs: 2),
          ],
        ),
        FreeClimbingBlock(blockId: 'free', sortOrder: 3, slotId: 'free'),
      ],
    );

WorkoutInstance progressInstance({
  String id = 'workout',
  String athlete = 'athlete',
  DateTime? date,
  int version = 1,
  bool? sent = true,
  int? attempts = 2,
  bool freeCounts = true,
  String programId = 'program',
  int programVersion = 0,
  String? programInstanceId,
  List<ExerciseActual>? actuals,
}) {
  final time = date ?? DateTime(2026, 11, 6, 12);
  return WorkoutInstance(
    id: id,
    programId: programId,
    programVersion: programVersion,
    athleteProgramInstanceId: programInstanceId,
    athleteId: athlete,
    workoutTemplateId: 'template',
    workoutTemplateVersion: version,
    scheduledDate: '2020-01-01',
    assignedBy: 'trainer',
    assignedAt: time,
    status: WorkoutInstanceStatus.completed,
    workoutType: WorkoutType.limit,
    completedAt: time,
    rpe: 7,
    durationMinutes: 45,
    createdAt: time,
    updatedAt: time,
    actuals: actuals ??
        [
          ExerciseActual(
              slotId: 'route',
              exerciseId: 'route-exercise',
              mode: ExerciseMode.reps,
              sent: sent,
              attempts: attempts),
          ExerciseActual(
              slotId: 'rope',
              exerciseId: 'rope-exercise',
              mode: ExerciseMode.reps,
              sent: true,
              attempts: 3),
          ExerciseActual(
              slotId: 'circuit',
              exerciseId: climbingCircuitExerciseId,
              mode: ExerciseMode.reps,
              climbingType: 'climbingCircuit',
              circuitRows: const [
                ClimbingCircuitResultRow(rowId: 'boulders', completed: true),
                ClimbingCircuitResultRow(rowId: 'ropes', completed: false),
              ]),
          ExerciseActual(
              slotId: 'free',
              exerciseId: freeClimbingExerciseId,
              mode: ExerciseMode.reps,
              climbingType: 'freeClimbing',
              freeRows: freeCounts
                  ? [
                      for (var i = 0; i < 4; i++)
                        FreeClimbingResultRow(
                            rowId: 'free-boulders-$i',
                            gradingSystem: ClimbingGradingSystem.vScale,
                            grade: 'V8',
                            attempts: 2,
                            sent: false),
                    ]
                  : const []),
        ],
  );
}

ClimbingSession progressSession({
  String id = 'workout',
  DateTime? date,
  int version = 1,
  String grade = 'V4',
  bool? sent = true,
  bool freeCounts = true,
  String? programId,
  String? programName,
}) =>
    ClimbingSession.fromWorkout(
      progressInstance(
          id: id,
          date: date,
          version: version,
          sent: sent,
          programId: programId ?? 'program',
          programVersion: programId == null ? 0 : 1,
          freeCounts: freeCounts),
      progressVersion(version: version, grade: grade),
      programName: programName,
    )!;
