import 'package:foundation_stage1/enums.dart';

/// Contract for load computation strategies.
///
/// Implement this to provide alternative load formulas. Each strategy
/// has a version and name for audit. The default v1 formula is
/// [DefaultLoadStrategy]. Programs can reference a strategy by name
/// via [Program.loadStrategyId].
abstract class LoadStrategy {
  /// Version number for this strategy, stored on each workout instance.
  int get version;

  /// Unique identifier for this strategy (e.g. "default_v1").
  String get name;

  /// Computes load points for a completed workout.
  ///
  /// [typeWeightOverrides] merges with the strategy's default weights,
  /// allowing per-program customization without a new strategy class.
  double computeLoadPoints({
    required WorkoutType workoutType,
    required int rpe,
    required int durationMinutes,
    Map<WorkoutType, int>? typeWeightOverrides,
  });

  /// Categorizes a load points value into easy/medium/hard.
  LoadBucket categorize(double loadPoints);
}

/// Default load computation strategy (v1).
///
/// Formula: LoadPoints = TypeWeight × EffortMap(RPE) × DurationModifier
///
/// All values are computed client-side on workout completion and stored
/// alongside `loadModelVersion` for future formula evolution.
class DefaultLoadStrategy implements LoadStrategy {
  /// Singleton instance for convenience.
  const DefaultLoadStrategy();

  /// Strategy version constant for use in static contexts.
  static const int strategyVersion = 1;

  @override
  int get version => strategyVersion;

  @override
  String get name => 'default_v1';

  /// Fixed type weights per workout type.
  ///
  /// Climbing: limit=5, power=4, power_endurance=4, endurance=2,
  ///           skill=2, cardio=2, mobility=1
  /// Strength: lower=4, legs=4, upper=3, full_body=3,
  ///           push=3, pull=3, core=2, conditioning=2
  static const Map<WorkoutType, int> defaultTypeWeights = {
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

  /// Resolves the effective type weight, applying per-program overrides.
  static int resolveTypeWeight(
    WorkoutType workoutType,
    Map<WorkoutType, int>? overrides,
  ) {
    if (overrides != null && overrides.containsKey(workoutType)) {
      return overrides[workoutType]!;
    }

    final weight = defaultTypeWeights[workoutType];
    if (weight == null) {
      throw ArgumentError('Unknown workout type: $workoutType');
    }

    return weight;
  }

  @override
  double computeLoadPoints({
    required WorkoutType workoutType,
    required int rpe,
    required int durationMinutes,
    Map<WorkoutType, int>? typeWeightOverrides,
  }) {
    final typeWeight = resolveTypeWeight(workoutType, typeWeightOverrides);
    final effort = effortFromRpe(rpe);
    final durMod = durationModifier(durationMinutes);

    return typeWeight * effort * durMod;
  }

  @override
  LoadBucket categorize(double loadPoints) {
    if (loadPoints <= 6) {
      return LoadBucket.easy;
    } else if (loadPoints <= 12) {
      return LoadBucket.medium;
    } else {
      return LoadBucket.hard;
    }
  }
}

/// Static convenience facade for load computation.
///
/// Delegates to a [LoadStrategy] instance. Uses [DefaultLoadStrategy]
/// when no strategy is specified.
///
/// For per-program overrides, pass [typeWeightOverrides] from the
/// program's configuration. For alternative formulas, pass a custom
/// [LoadStrategy] via the [strategy] parameter.
class LoadModel {
  /// Current default model version.
  static const int currentVersion = DefaultLoadStrategy.strategyVersion;

  /// Default type weights (exposed for backward compatibility).
  static const Map<WorkoutType, int> typeWeights =
      DefaultLoadStrategy.defaultTypeWeights;

  static const LoadStrategy _default = DefaultLoadStrategy();

  /// Computes load points using the specified (or default) strategy.
  ///
  /// [typeWeightOverrides] allows per-program weight customization.
  /// [strategy] allows plugging in an entirely different formula.
  static double computeLoadPoints({
    required WorkoutType workoutType,
    required int rpe,
    required int durationMinutes,
    Map<WorkoutType, int>? typeWeightOverrides,
    LoadStrategy? strategy,
  }) {
    final s = strategy ?? _default;

    return s.computeLoadPoints(
      workoutType: workoutType,
      rpe: rpe,
      durationMinutes: durationMinutes,
      typeWeightOverrides: typeWeightOverrides,
    );
  }

  /// Categorizes load points into easy/medium/hard.
  static LoadBucket categorize(
    double loadPoints, {
    LoadStrategy? strategy,
  }) {
    final s = strategy ?? _default;

    return s.categorize(loadPoints);
  }

  /// Validates per-program type weight overrides.
  ///
  /// Ensures all values are positive integers.
  static void validateTypeWeightOverrides(Map<WorkoutType, int> overrides) {
    for (final entry in overrides.entries) {
      if (entry.value < 1) {
        throw ArgumentError(
          'Type weight for ${entry.key} must be >= 1, got ${entry.value}',
        );
      }
    }
  }
}

/// Load intensity buckets for dashboard display.
enum LoadBucket {
  easy,
  medium,
  hard,
}
