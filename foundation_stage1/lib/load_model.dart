import 'package:foundation_stage1/enums.dart';

/// Load computation logic for workout intensity tracking.
///
/// Implements the v1 formula:
/// LoadPoints = TypeWeight × EffortMap(RPE) × DurationModifier(minutes)
///
/// All values are computed client-side on workout completion and stored
/// alongside `loadModelVersion` for future formula evolution.
class LoadModel {
  /// Current model version. Stored on every workout instance so
  /// historical values remain interpretable if the formula changes.
  static const int currentVersion = 1;

  /// Fixed type weights per workout type.
  ///
  /// Climbing: limit=5, power=4, power_endurance=4, endurance=2,
  ///           skill=2, cardio=2, mobility=1
  /// Strength: lower=4, legs=4, upper=3, full_body=3,
  ///           push=3, pull=3, core=2, conditioning=2
  static const Map<WorkoutType, int> typeWeights = {
    // Climbing
    WorkoutType.limit: 5,
    WorkoutType.power: 4,
    WorkoutType.powerEndurance: 4,
    WorkoutType.endurance: 2,
    WorkoutType.skill: 2,
    WorkoutType.cardio: 2,
    WorkoutType.mobility: 1,
    // Strength
    WorkoutType.lower: 4,
    WorkoutType.legs: 4,
    WorkoutType.upper: 3,
    WorkoutType.fullBody: 3,
    WorkoutType.push: 3,
    WorkoutType.pull: 3,
    WorkoutType.core: 2,
    WorkoutType.conditioning: 2,
  };

  /// Maps RPE (1–10) to effort multiplier (1–5).
  ///
  /// RPE 1–2 → 1, 3–4 → 2, 5–6 → 3, 7–8 → 4, 9–10 → 5
  static int effortFromRpe(int rpe) {
    if (rpe < 1 || rpe > 10) {
      throw ArgumentError('RPE must be between 1 and 10, got $rpe');
    }

    return (rpe + 1) ~/ 2;
  }

  /// Maps workout duration to a modifier.
  ///
  /// <30 min → 0.75, 30–75 min → 1.0, >75 min → 1.25
  static double durationModifier(int durationMinutes) {
    if (durationMinutes < 0) {
      throw ArgumentError(
        'durationMinutes must be >= 0, got $durationMinutes',
      );
    }

    if (durationMinutes < 30) {
      return 0.75;
    } else if (durationMinutes <= 75) {
      return 1.0;
    } else {
      return 1.25;
    }
  }

  /// Computes load points for a completed workout.
  ///
  /// Returns the load points value:
  /// LoadPoints = TypeWeight × Effort × DurationModifier
  static double computeLoadPoints({
    required WorkoutType workoutType,
    required int rpe,
    required int durationMinutes,
  }) {
    final typeWeight = typeWeights[workoutType];
    if (typeWeight == null) {
      throw ArgumentError('Unknown workout type: $workoutType');
    }

    final effort = effortFromRpe(rpe);
    final durMod = durationModifier(durationMinutes);

    return typeWeight * effort * durMod;
  }

  /// Categorizes a load points value into a bucket.
  ///
  /// easy ≤ 6, medium 7–12, hard ≥ 13
  static LoadBucket categorize(double loadPoints) {
    if (loadPoints <= 6) {
      return LoadBucket.easy;
    } else if (loadPoints <= 12) {
      return LoadBucket.medium;
    } else {
      return LoadBucket.hard;
    }
  }
}

/// Load intensity buckets for dashboard display.
enum LoadBucket {
  easy,
  medium,
  hard,
}
